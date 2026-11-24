package storage

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"backend/internal/config"

	"github.com/google/uuid"
)

// StorageService gestiona el almacenamiento de videos y thumbnails.
// Soporta cualquier proveedor S3-compatible (Cloudflare R2, MinIO en Bare Metal,
// Hetzner Object Storage, Backblaze B2, AWS S3) con fallback local para desarrollo.
type StorageService struct {
	s3Endpoint      string // Ej: https://<account_id>.r2.cloudflarestorage.com o https://s3.tudominio.com
	s3Region        string // Ej: auto (R2) o us-east-1 (MinIO/S3)
	s3AccessKeyID   string
	s3SecretKey     string
	s3BucketName    string
	publicBaseURL   string // Ej: https://media.tudominio.com (dominio propio detrás de Cloudflare CDN)
	localStorageDir string
	baseURL         string
}

var Instance *StorageService

func InitStorage() {
	uploadDir := config.GetEnv("UPLOAD_DIR", "./uploads/reels")
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		log.Printf("Aviso: no se pudo crear el directorio de subidas local: %v", err)
	}

	// Prioridad a variables S3 genéricas (portabilidad Bare Metal), con fallback 100% compatible a R2_*
	s3Endpoint := strings.TrimRight(config.GetEnv("S3_ENDPOINT", ""), "/")
	if s3Endpoint == "" {
		if r2Acc := config.GetEnv("R2_ACCOUNT_ID", ""); r2Acc != "" {
			s3Endpoint = fmt.Sprintf("https://%s.r2.cloudflarestorage.com", r2Acc)
		}
	}

	s3Region := config.GetEnv("S3_REGION", "auto")
	accessKey := config.GetEnv("S3_ACCESS_KEY_ID", config.GetEnv("R2_ACCESS_KEY_ID", ""))
	secretKey := config.GetEnv("S3_SECRET_ACCESS_KEY", config.GetEnv("R2_SECRET_ACCESS_KEY", ""))
	bucket := config.GetEnv("S3_BUCKET_NAME", config.GetEnv("R2_BUCKET_NAME", ""))

	publicURL := strings.TrimRight(config.GetEnv("MEDIA_PUBLIC_URL", config.GetEnv("R2_PUBLIC_URL", "")), "/")
	baseURL := strings.TrimRight(config.GetEnv("BASE_URL", "http://localhost:8080"), "/")

	Instance = &StorageService{
		s3Endpoint:      s3Endpoint,
		s3Region:        s3Region,
		s3AccessKeyID:   accessKey,
		s3SecretKey:     secretKey,
		s3BucketName:    bucket,
		publicBaseURL:   publicURL,
		localStorageDir: uploadDir,
		baseURL:         baseURL,
	}

	if Instance.IsObjectStorageConfigured() {
		log.Printf("[Storage] Object Storage S3-compatible configurado (bucket=%s, region=%s).", bucket, s3Region)
	} else {
		log.Printf("[Storage] Object Storage no configurado en .env. Usando almacenamiento local en: %s", uploadDir)
	}
}

// IsObjectStorageConfigured indica si hay almacenamiento S3/R2 listo para producción
func (s *StorageService) IsObjectStorageConfigured() bool {
	return s.s3Endpoint != "" && s.s3AccessKeyID != "" && s.s3SecretKey != "" && s.s3BucketName != ""
}

// IsR2Configured alias retrocompatible
func (s *StorageService) IsR2Configured() bool {
	return s.IsObjectStorageConfigured()
}

// PublicURLForKey construye la URL pública final a partir de una clave relativa o devuelve la URL si ya es absoluta.
func (s *StorageService) PublicURLForKey(objectKey string) string {
	trimmed := strings.TrimSpace(objectKey)
	if trimmed == "" {
		return ""
	}
	lower := strings.ToLower(trimmed)
	if strings.HasPrefix(lower, "http://") || strings.HasPrefix(lower, "https://") {
		return trimmed
	}
	cleanKey := strings.TrimLeft(trimmed, "/")
	if s.publicBaseURL != "" {
		return fmt.Sprintf("%s/%s", s.publicBaseURL, cleanKey)
	}
	if s.IsObjectStorageConfigured() {
		return fmt.Sprintf("%s/%s/%s", s.s3Endpoint, s.s3BucketName, cleanKey)
	}
	return fmt.Sprintf("%s/uploads/reels/%s", s.baseURL, cleanKey)
}

// PresignedUploadResult contiene la URL prefirmada para subida directa desde el cliente sin consumir RAM del servidor Go.
type PresignedUploadResult struct {
	UploadURL string `json:"upload_url"`
	ObjectKey string `json:"object_key"`
	PublicURL string `json:"public_url"`
	ExpiresIn int    `json:"expires_in"`
}

// GeneratePresignedUploadURL genera una URL PUT prefirmada con AWS SigV4 (Query String Auth)
// para que Flutter suba el video comprimido directo a Cloudflare R2 / MinIO / S3.
func (s *StorageService) GeneratePresignedUploadURL(prefix, filename, contentType string, ttl time.Duration) (*PresignedUploadResult, error) {
	if !s.IsObjectStorageConfigured() {
		return nil, fmt.Errorf("object storage no configurado")
	}

	ext := strings.ToLower(filepath.Ext(filename))
	if ext == "" {
		ext = ".mp4"
	}
	cleanPrefix := strings.Trim(prefix, "/")
	objectKey := fmt.Sprintf("%s%s", uuid.New().String(), ext)
	if cleanPrefix != "" {
		objectKey = fmt.Sprintf("%s/%s", cleanPrefix, objectKey)
	}

	if ttl <= 0 || ttl > 30*time.Minute {
		ttl = 10 * time.Minute
	}

	parsedEndpoint, err := url.Parse(s.s3Endpoint)
	if err != nil {
		return nil, fmt.Errorf("endpoint S3 inválido: %w", err)
	}

	now := time.Now().UTC()
	dateStamp := now.Format("20060102")
	amzDate := now.Format("20060102T150405Z")
	expiresSec := int(ttl.Seconds())

	region := s.s3Region
	if region == "" {
		region = "auto"
	}
	service := "s3"
	credentialScope := fmt.Sprintf("%s/%s/%s/aws4_request", dateStamp, region, service)
	credential := fmt.Sprintf("%s/%s", s.s3AccessKeyID, credentialScope)

	canonicalURI := fmt.Sprintf("/%s/%s", s.s3BucketName, objectKey)

	// Parámetros ordenados alfabéticamente (requisito estricto SigV4)
	queryParams := url.Values{}
	queryParams.Set("X-Amz-Algorithm", "AWS4-HMAC-SHA256")
	queryParams.Set("X-Amz-Credential", credential)
	queryParams.Set("X-Amz-Date", amzDate)
	queryParams.Set("X-Amz-Expires", fmt.Sprintf("%d", expiresSec))
	queryParams.Set("X-Amz-SignedHeaders", "host")

	// url.Values.Encode ordena por clave; SigV4 exige %20 en vez de '+'
	canonicalQuery := strings.ReplaceAll(queryParams.Encode(), "+", "%20")
	canonicalHeaders := fmt.Sprintf("host:%s\n", parsedEndpoint.Host)
	signedHeaders := "host"

	canonicalRequest := fmt.Sprintf("PUT\n%s\n%s\n%s\n%s\nUNSIGNED-PAYLOAD",
		canonicalURI,
		canonicalQuery,
		canonicalHeaders,
		signedHeaders,
	)

	stringToSign := fmt.Sprintf("AWS4-HMAC-SHA256\n%s\n%s\n%s",
		amzDate,
		credentialScope,
		sha256Hex([]byte(canonicalRequest)),
	)

	kDate := hmacSHA256([]byte("AWS4"+s.s3SecretKey), dateStamp)
	kRegion := hmacSHA256(kDate, region)
	kService := hmacSHA256(kRegion, service)
	kSigning := hmacSHA256(kService, "aws4_request")
	signature := hex.EncodeToString(hmacSHA256(kSigning, stringToSign))

	uploadURL := fmt.Sprintf("%s%s?%s&X-Amz-Signature=%s",
		s.s3Endpoint,
		canonicalURI,
		canonicalQuery,
		signature,
	)

	return &PresignedUploadResult{
		UploadURL: uploadURL,
		ObjectKey: objectKey,
		PublicURL: s.PublicURLForKey(objectKey),
		ExpiresIn: expiresSec,
	}, nil
}

// UploadMedia sube un archivo (video o thumbnail) devolviendo la URL pública y la clave del objeto.
func (s *StorageService) UploadMedia(fileHeader io.Reader, filename string, contentType string) (string, string, error) {
	ext := strings.ToLower(filepath.Ext(filename))
	if ext == "" {
		ext = ".mp4"
	}
	uniqueName := fmt.Sprintf("reels/%s%s", uuid.New().String(), ext)

	if s.IsObjectStorageConfigured() {
		publicURL, err := s.uploadToS3(fileHeader, uniqueName, contentType)
		if err == nil {
			return publicURL, uniqueName, nil
		}
		log.Printf("[Storage] Error subiendo a Object Storage, recurriendo a local: %v", err)
	}

	// Fallback a almacenamiento local
	localFilename := filepath.Base(uniqueName)
	destPath := filepath.Join(s.localStorageDir, localFilename)
	outFile, err := os.Create(destPath)
	if err != nil {
		return "", "", fmt.Errorf("error creando archivo local: %w", err)
	}
	defer outFile.Close()

	if _, err := io.Copy(outFile, fileHeader); err != nil {
		return "", "", fmt.Errorf("error escribiendo archivo local: %w", err)
	}

	publicURL := fmt.Sprintf("%s/uploads/reels/%s", s.baseURL, localFilename)
	return publicURL, localFilename, nil
}

// uploadToS3 realiza un PUT HTTP directo al endpoint S3-compatible usando bytes.NewReader (sin duplicar memoria).
func (s *StorageService) uploadToS3(reader io.Reader, objectKey string, contentType string) (string, error) {
	endpoint := fmt.Sprintf("%s/%s/%s", s.s3Endpoint, s.s3BucketName, objectKey)

	payloadBytes, err := io.ReadAll(reader)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest(http.MethodPut, endpoint, bytes.NewReader(payloadBytes))
	if err != nil {
		return "", err
	}
	req.ContentLength = int64(len(payloadBytes))

	if contentType == "" {
		contentType = "application/octet-stream"
	}
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("Cache-Control", "public, max-age=31536000, immutable")

	now := time.Now().UTC()
	dateStamp := now.Format("20060102")
	amzDate := now.Format("20060102T150405Z")
	req.Header.Set("x-amz-date", amzDate)
	req.Header.Set("x-amz-content-sha256", sha256Hex(payloadBytes))

	authHeader := s.calculateSigV4(req, dateStamp, amzDate, objectKey, payloadBytes)
	req.Header.Set("Authorization", authHeader)

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("s3 put error status %d: %s", resp.StatusCode, string(body))
	}

	return s.PublicURLForKey(objectKey), nil
}

func sha256Hex(data []byte) string {
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:])
}

func hmacSHA256(key []byte, data string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(data))
	return h.Sum(nil)
}

func (s *StorageService) calculateSigV4(req *http.Request, dateStamp, amzDate, objectKey string, payload []byte) string {
	region := s.s3Region
	if region == "" {
		region = "auto"
	}
	service := "s3"

	payloadHash := sha256Hex(payload)
	canonicalURI := fmt.Sprintf("/%s/%s", s.s3BucketName, objectKey)
	canonicalQuery := ""
	canonicalHeaders := fmt.Sprintf("host:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\n", req.URL.Host, payloadHash, amzDate)
	signedHeaders := "host;x-amz-content-sha256;x-amz-date"

	canonicalRequest := fmt.Sprintf("%s\n%s\n%s\n%s\n%s\n%s",
		req.Method,
		canonicalURI,
		canonicalQuery,
		canonicalHeaders,
		signedHeaders,
		payloadHash,
	)

	credentialScope := fmt.Sprintf("%s/%s/%s/aws4_request", dateStamp, region, service)
	stringToSign := fmt.Sprintf("AWS4-HMAC-SHA256\n%s\n%s\n%s",
		amzDate,
		credentialScope,
		sha256Hex([]byte(canonicalRequest)),
	)

	kDate := hmacSHA256([]byte("AWS4"+s.s3SecretKey), dateStamp)
	kRegion := hmacSHA256(kDate, region)
	kService := hmacSHA256(kRegion, service)
	kSigning := hmacSHA256(kService, "aws4_request")
	signature := hex.EncodeToString(hmacSHA256(kSigning, stringToSign))

	return fmt.Sprintf("AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		s.s3AccessKeyID,
		credentialScope,
		signedHeaders,
		signature,
	)
}

// DeleteObject elimina un archivo de Object Storage (R2/S3) o del disco local para evitar archivos huérfanos.
func (s *StorageService) DeleteObject(objectKey string) error {
	cleanKey := strings.TrimLeft(strings.TrimSpace(objectKey), "/")
	if cleanKey == "" {
		return nil
	}

	if s.IsObjectStorageConfigured() {
		endpoint := fmt.Sprintf("%s/%s/%s", s.s3Endpoint, s.s3BucketName, cleanKey)
		req, err := http.NewRequest(http.MethodDelete, endpoint, nil)
		if err != nil {
			return err
		}

		now := time.Now().UTC()
		dateStamp := now.Format("20060102")
		amzDate := now.Format("20060102T150405Z")
		emptyHash := sha256Hex(nil)
		req.Header.Set("x-amz-date", amzDate)
		req.Header.Set("x-amz-content-sha256", emptyHash)
		req.Header.Set("Authorization", s.calculateSigV4(req, dateStamp, amzDate, cleanKey, nil))

		client := &http.Client{Timeout: 20 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNotFound {
			body, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("s3 delete error status %d: %s", resp.StatusCode, string(body))
		}
		return nil
	}

	// Fallback local
	localPath := filepath.Join(s.localStorageDir, filepath.Base(cleanKey))
	if err := os.Remove(localPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
