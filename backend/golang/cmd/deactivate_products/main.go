package main

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/option"
)

func main() {
	// 1. Configurar credenciales (extraídas de tu .env)
	packageName := "com.drafting.app"
	credentialsJSON := `{
  "type": "service_account",
  "project_id": "project-793e159d-7403-492f-969",
  "private_key_id": "6cf3a0a0fd67126d6056ee162f4443ed38c66b34",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDiKo14gEs7Vq0C\nhBz1qd3ewn3p0BbdGlklxTYQ3bMX3+4bsjaxsePc12xPlmqKEbBhBjxaHOl9SNxQ\nR+OER19d5PEZIbkCz0W93QuDLwvXet2y4pvwmobUv5mJikAaNdZt6gg0fbFvv4ZW\nbkrKJnJgYi0fkxhTUi6CM+sQRUgCThIuM8EwloBYDN3fwSVaXqthNzCkVLbKmrTq\n2ntNwOtwCmS9YmOC0ijUiG0UdZL+7JnCXbfPmYwgWcVp5AAn0xRoUOdQ5sKnPx6C\n8PkzqI+tF20AhHDkiqLLG2VJj1+eE9V1LAkj0o9a1M5gs5yWf7yvbMjvOGoJIvUP\n+J693zi9AgMBAAECggEACLK7QyWn/w271KtxE6+nRVB0mD/1CSbgw9ecVzS3lRT7\nKtyFRvtA+LbeRwdRbKL2hhy/yHVxM2zQcFP7d5RpIgrSjPVjkKyZEY7FSRPPoEds\n7FrTxYKj6d2+kXAcPAXTC+Ii06X744DZsUxHmxO0dWmBM8Qr/NRdzoshoLwRY2k7\nvdQS89cyMTE/E8SP5Z2zxVnkcoipQiM0BjasXL4sQRV3HQJpoYGMQiyIlCXiHLPs\nMzkWbt57pYdJjqWgH3KFChgCvL8ZMLbicY8zF4P8gEhRrnku5aBSD4AdE5Fr7oYq\nRQqxtr2EGkmRdxuNqwIj/vYjY58QfgNBsSVe7lso7wKBgQD0/mnziMdc3AW5+7GE\nuH00+j8B8BWCm4nghxSuJlrPuTa9yelL5tgjd3n5X9djEUifL1uzV12Yyh4qSblW\nRBCniS5Sxhe1YW+FbsV1RysKfBS8NSFIogeO1agXCFEnr0Veekw13DfTfW2vkz7m\ncyVLlaWVbAEGZ9NDxQr8ttithwKBgQDsU5wE0KzBOsb5ITC4vIgyS8ieYnlsRPUV\n27QR+WKnv8sMuVK8gwYUoHemXn4qylepNERtMJZK/PZHFePLC0Eus3TD5a1jhbBm\nmwlfl3h9su7jf2DImlhzmjm1lLs/Z05b1y1Yit6LvfNO4HJy8fXWz1DXAmIWLWXd\nOvnQKqqYmwKBgQCDbPu/hk+Uk/+KbugjD6kzQ0+LpZSUdQX46d4BMlgi+PPRykAZ\n1KN8GzrWuUBdR8dSheBGjAaM0VhvTQ9cpLTeeyvbgaL0TWm7BdpteJkxTbD96e6J\n/UnaqOk8Odz3UgH/ldHOTu2vyaiOuInUrE6EhqnGR6MhIY9m2oxzV09TfwKBgCgq\n0dLTsPkqx1Tiukg76x45WUDqVd78HXf4nrOLYqRGafmgqhpWXrs0xwFlACa/u4SL\n2LGCV5kpQ6azZsNFB3ArmkYNjJnkyCW4ZjB0K0uaFRZfuRB/g1cquHJPdEADjAL6\nIL/y4n5365nVdj5pN7KqDABvbEJ+ttiSRJGIHvTPAoGBAJkg0WAxqbELPrM6Ka1B\ntuhLx7fnHkiLknwYkE27tgosbd91UhAS5HCk3RbVVo/pnhL3kNjJ/PU7R+DT6umf\nt5G33OpyPog1p1kMwbSRw2f5D6LF0wTHE/cxQXDcKBSMQDyygjxWIUo381/pKR1z\nWLX571is5BQmeJDHEGhFW2Ms\n-----END PRIVATE KEY-----\n",
  "client_email": "drafting@project-793e159d-7403-492f-969.iam.gserviceaccount.com",
  "client_id": "115355731060150613238",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/drafting%40project-793e159d-7403-492f-969.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}`

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
