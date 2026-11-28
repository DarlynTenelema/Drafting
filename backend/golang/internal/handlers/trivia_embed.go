package handlers

import "embed"

//go:embed trivia_data/trivia_questions_*.json
var embeddedTriviaFS embed.FS
