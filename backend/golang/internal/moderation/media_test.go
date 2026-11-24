package moderation

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"testing"
)

func makeTestGradientJPEG(t *testing.T, invert bool) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 64, 64))
	for y := 0; y < 64; y++ {
		for x := 0; x < 64; x++ {
			v := uint8(x * 4)
			if invert {
				v = 255 - v
			}
			img.Set(x, y, color.RGBA{R: v, G: v, B: v, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 80}); err != nil {
		t.Fatalf("failed encoding test jpeg: %v", err)
	}
	return buf.Bytes()
}

func TestComputeImageDHashAndHamming(t *testing.T) {
	imgA := makeTestGradientJPEG(t, false)
	imgB := makeTestGradientJPEG(t, true)

	hashA1, err := ComputeImageDHash(imgA)
	if err != nil {
		t.Fatalf("unexpected error computing dHash: %v", err)
	}
	hashA2, err := ComputeImageDHash(imgA)
	if err != nil {
		t.Fatalf("unexpected error computing dHash: %v", err)
	}
	hashB, err := ComputeImageDHash(imgB)
	if err != nil {
		t.Fatalf("unexpected error computing dHash for inverted image: %v", err)
	}

	if len(hashA1) != 16 {
		t.Fatalf("expected 16-char hex dHash, got %q", hashA1)
	}
	if dist := HammingDistanceHex(hashA1, hashA2); dist != 0 {
		t.Fatalf("expected 0 hamming distance for identical images, got %d", dist)
	}
	if dist := HammingDistanceHex(hashA1, hashB); dist < 32 {
		t.Fatalf("expected large hamming distance for inverted images, got %d", dist)
	}
}
