package main
import (
    "fmt"
    "net/http"
)
func main() {
    req, err := http.NewRequest("POST", "https://test.com/storage/v1/object/fanarts/user123_image picker.jpg", nil)
    fmt.Printf("req err: %v\n", err)
    
    if err == nil {
        client := &http.Client{}
        _, err = client.Do(req)
        fmt.Printf("do err: %v\n", err)
    }
}
