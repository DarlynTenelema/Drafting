package moderation

import (
	"bytes"
	"context"
	"encoding/hex"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"math/bits"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	MaxExtractedFrames       = 5
	MaxHammingMatchThreshold = 6 // Distancia de Hamming <= 6 bits de 64 indica imagen prácticamente idéntica
)

// IsFFmpegAvailable verifica si ffmpeg está disponible en el PATH del contenedor/servidor.
func IsFFmpegAvailable() bool {
	_, err := exec.LookPath("ffmpeg")
	return err == nil
}

// ComputeImageDHash calcula un perceptual difference hash (dHash) de 64 bits (16 caracteres hex)
// en Go puro, resistente a recompresión, cambios leves de brillo y redimensionamiento.
func ComputeImageDHash(imgBytes []byte) (string, error) {
	img, _, err := image.Decode(bytes.NewReader(imgBytes))
	if err != nil {
		return "", fmt.Errorf("error decodificando imagen para dHash: %w", err)
	}

	bounds := img.Bounds()
	w := bounds.Dx()
	h := bounds.Dy()
	if w <= 0 || h <= 0 {
		return "", fmt.Errorf("dimensiones de imagen inválidas")
	}

	// Muestrear una grilla de 9x8 en escala de grises (nearest-neighbor box sampling rápido)
	var gray [8][9]uint32
	for row := 0; row < 8; row++ {
		srcY := bounds.Min.Y + (row*h)/8 + h/16
		if srcY >= bounds.Max.Y {
			srcY = bounds.Max.Y - 1
		}
		for col := 0; col < 9; col++ {
			srcX := bounds.Min.X + (col*w)/9 + w/18
			if srcX >= bounds.Max.X {
				srcX = bounds.Max.X - 1
			}
			r, g, b, _ := img.At(srcX, srcY).RGBA()
			// Luminancia estándar Rec. 601
			gray[row][col] = (299*r + 587*g + 114*b) / 1000
		}
	}

	var hash uint64
	var bit uint
	for row := 0; row < 8; row++ {
		for col := 0; col < 8; col++ {
			if gray[row][col] > gray[row][col+1] {
				hash |= 1 << bit
			}
			bit++
		}
	}

	var buf [8]byte
	for i := 0; i < 8; i++ {
		buf[i] = byte(hash >> (56 - 8*i))
	}
	return hex.EncodeToString(buf[:]), nil
}

// HammingDistanceHex calcula cuántos bits difieren entre dos dHashes hexadecimales de 64 bits.
func HammingDistanceHex(a, b string) int {
	a = strings.TrimSpace(a)
	b = strings.TrimSpace(b)
	if len(a) != 16 || len(b) != 16 {
		return 64
	}
	ua, errA := strconv.ParseUint(a, 16, 64)
	ub, errB := strconv.ParseUint(b, 16, 64)
	if errA != nil || errB != nil {
		return 64
	}
	return bits.OnesCount64(ua ^ ub)
}

// ExtractKeyframesAndHashes descarga/lee el video temporalmente y extrae hasta 5 fotogramas clave
// (10%, 30%, 50%, 70%, 90%) junto con sus dHashes perceptuales.
// Si ffmpeg no está instalado (ej. entorno local Windows sin ffmpeg), recurre al thumbnailURL si existe.
func ExtractKeyframesAndHashes(ctx context.Context, videoURL, thumbnailURL string, durationSeconds int) ([][]byte, []string, error) {
	if durationSeconds <= 0 {
		durationSeconds = 15
	}

	if IsFFmpegAvailable() && strings.TrimSpace(videoURL) != "" {
		frames, hashes, err := extractFramesWithFFmpeg(ctx, videoURL, durationSeconds)
		if err == nil && len(frames) > 0 {
			return frames, hashes, nil
		}
	}

	// Fallback seguro: analizar al menos el thumbnail si existe
	if strings.TrimSpace(thumbnailURL) != "" {
		thumbBytes, err := fetchSmallURL(ctx, thumbnailURL, 5<<20)
		if err == nil && len(thumbBytes) > 0 {
			var hashes []string
			if h, errH := ComputeImageDHash(thumbBytes); errH == nil {
				hashes = append(hashes, h)
			}
			return [][]byte{thumbBytes}, hashes, nil
		}
	}

	return nil, nil, fmt.Errorf("no se pudieron extraer fotogramas (ffmpeg=%v)", IsFFmpegAvailable())
}

func extractFramesWithFFmpeg(ctx context.Context, videoURL string, durationSeconds int) ([][]byte, []string, error) {
	tmpDir, err := os.MkdirTemp("", "reel-mod-*")
	if err != nil {
		return nil, nil, err
	}
	defer os.RemoveAll(tmpDir)

	// Descargar en streaming directo a disco si es HTTP(S) para evitar múltiples seek requests contra R2/S3
	// y no retener hasta 18 MB por video en la RAM del servidor Go.
	inputPath := videoURL
	if strings.HasPrefix(strings.ToLower(videoURL), "http://") || strings.HasPrefix(strings.ToLower(videoURL), "https://") {
		localVid := filepath.Join(tmpDir, "input.mp4")
		if err := downloadURLToFile(ctx, videoURL, localVid, 18<<20); err != nil {
			return nil, nil, fmt.Errorf("error descargando video para moderación: %w", err)
		}
		inputPath = localVid
	}

	// Extraer 5 fotogramas distribuidos en el video (escala 384px de ancho, JPEG ligero)
	percents := []float64{0.10, 0.30, 0.50, 0.70, 0.90}
	frames := make([][]byte, 0, len(percents))
	hashes := make([]string, 0, len(percents))

	for i, p := range percents {
		ts := float64(durationSeconds) * p
		if ts < 0.2 {
			ts = 0.2
		}
		outFile := filepath.Join(tmpDir, fmt.Sprintf("frame_%d.jpg", i))
		cmdCtx, cancel := context.WithTimeout(ctx, 12*time.Second)
		cmd := exec.CommandContext(
			cmdCtx,
			"ffmpeg",
			"-hide_banner",
			"-loglevel", "error",
			"-ss", fmt.Sprintf("%.2f", ts),
			"-i", inputPath,
			"-frames:v", "1",
			"-vf", "scale=384:-2",
			"-q:v", "6",
			"-y", outFile,
		)
		err := cmd.Run()
		cancel()
		if err != nil {
			continue
		}
		data, err := os.ReadFile(outFile)
		if err != nil || len(data) == 0 {
			continue
		}
		frames = append(frames, data)
		if h, errH := ComputeImageDHash(data); errH == nil {
			hashes = append(hashes, h)
		}
	}

	if len(frames) == 0 {
		return nil, nil, fmt.Errorf("ffmpeg no extrajo ningún fotograma")
	}
	return frames, hashes, nil
}

// ExtractAudioTrack extrae la pista de audio en MP3 mono ligero (32kbps) SOLO bajo demanda
// cuando un video entra en cuarentena por reportes de insultos/odio.
func ExtractAudioTrack(ctx context.Context, videoURL string) ([]byte, error) {
	if !IsFFmpegAvailable() {
		return nil, fmt.Errorf("ffmpeg no disponible")
	}
	tmpDir, err := os.MkdirTemp("", "reel-audio-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmpDir)

	inputPath := videoURL
	if strings.HasPrefix(strings.ToLower(videoURL), "http://") || strings.HasPrefix(strings.ToLower(videoURL), "https://") {
		localVid := filepath.Join(tmpDir, "input.mp4")
		if err := downloadURLToFile(ctx, videoURL, localVid, 18<<20); err != nil {
			return nil, err
		}
		inputPath = localVid
	}

	outAudio := filepath.Join(tmpDir, "audio.mp3")
	cmdCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	cmd := exec.CommandContext(
		cmdCtx,
		"ffmpeg",
		"-hide_banner",
		"-loglevel", "error",
		"-i", inputPath,
		"-vn",
		"-ac", "1",
		"-ar", "16000",
		"-b:a", "32k",
		"-t", "35",
		"-y", outAudio,
	)
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("el video no tiene pista de audio o falló extracción: %w", err)
	}

	data, err := os.ReadFile(outAudio)
	if err != nil || len(data) == 0 {
		return nil, fmt.Errorf("audio extraído vacío")
	}
	return data, nil
}

func fetchSmallURL(ctx context.Context, rawURL string, maxBytes int64) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	client := &http.Client{Timeout: 25 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("http status %d descargando media", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, maxBytes))
}

// downloadURLToFile descarga en streaming directo al disco temporal (usa ~32 KB de buffer RAM en lugar de 18 MB).
func downloadURLToFile(ctx context.Context, rawURL, destPath string, maxBytes int64) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("http status %d descargando media", resp.StatusCode)
	}

	outFile, err := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(outFile, io.LimitReader(resp.Body, maxBytes))
	closeErr := outFile.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}
