package main

import (
	"fmt"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

type Group struct {
	ID      string
	Name    string
	Status  string
	OwnerID string
}

func main() {
	dsn := "host=localhost user=postgres password=postgres dbname=postgres port=54322 sslmode=disable"
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		fmt.Println("Error connecting:", err)
		return
	}

	var groups []Group
	db.Table("groups").Find(&groups)

	fmt.Printf("Total groups: %d\n", len(groups))
	for _, g := range groups {
		fmt.Printf("- %s (Status: %s, Owner: %s)\n", g.Name, g.Status, g.OwnerID)
	}
}
