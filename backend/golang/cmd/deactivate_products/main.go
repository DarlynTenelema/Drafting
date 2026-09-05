package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/option"
)

func main() {
	// 1. Configurar credenciales (extraídas de tu .env)
	packageName := "com.drafting.app"
	credentialsJSON := os.Getenv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
	if credentialsJSON == "" {
		log.Fatalf("Error: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON no está configurada en las variables de entorno.")
	}

	ctx := context.Background()
	service, err := androidpublisher.NewService(ctx, option.WithCredentialsJSON([]byte(credentialsJSON)))
	if err != nil {
		log.Fatalf("Error inicializando Android Publisher: %v", err)
	}

	// 2. Lista de productos exactos que obtuvimos de tu archivo products.go
	productIDs := []string{
		"sub_plus_1d", "sub_plus_1w", "sub_plus_1m", "sub_plus_1y",
		"sub_pro_1d", "sub_pro_1w", "sub_pro_1m", "sub_pro_1y",
		"sub_ultra_1d", "sub_ultra_1w", "sub_ultra_1m", "sub_ultra_1y",
		"sub_creator_plus_1d", "sub_creator_plus_1w", "sub_creator_plus_1m", "sub_creator_plus_1y",
		"sub_creator_pro_1d", "sub_creator_pro_1w", "sub_creator_pro_1m", "sub_creator_pro_1y",
		"sub_creator_ultra_1d", "sub_creator_ultra_1w", "sub_creator_ultra_1m", "sub_creator_ultra_1y",
	}

	fmt.Printf("Iniciando desactivación masiva de %d productos...\n", len(productIDs))

	successCount := 0
	errorCount := 0

	// 3. Iterar y parchear el estado de cada producto a "inactive"
	for _, sku := range productIDs {
		productPatch := &androidpublisher.InAppProduct{
			PackageName: packageName,
			Sku:         sku,
			Status:      "inactive", 
		}

		fmt.Printf("Procesando: %s ... ", sku)
		
		_, err := service.Inappproducts.Patch(packageName, sku, productPatch).Context(ctx).Do()
		if err != nil {
			if strings.Contains(err.Error(), "Inappproduct not found") {
				fmt.Println("Omitido (No existe en la consola).")
			} else {
				fmt.Printf("Error: %v\n", err)
				errorCount++
			}
		} else {
			fmt.Println("DESACTIVADO correctamente.")
			successCount++
		}
		
		// Un pequeño sleep para no saturar la API de Google Play
		time.Sleep(500 * time.Millisecond)
	}

	fmt.Printf("\n--- RESUMEN ---\n")
	fmt.Printf("Desactivados con éxito: %d\n", successCount)
	fmt.Printf("Errores/No encontrados: %d\n", len(productIDs)-successCount)
	fmt.Println("¡Proceso finalizado!")
}
