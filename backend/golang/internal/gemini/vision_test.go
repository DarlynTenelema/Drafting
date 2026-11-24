package gemini

import "testing"

func TestParseDraftVisionJSON(t *testing.T) {
	raw := "```json\n{\"role\":\"Top\",\"bans\":[\"Darius\",\"Lux\"],\"allies\":[\"Lee Sin\"],\"enemies\":[\"Ahri\",\"Vi\"]}\n```"
	state, err := parseDraftVisionJSON(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if state.Role != "Baron" {
		t.Fatalf("expected Baron, got %s", state.Role)
	}
	if len(state.Bans) != 2 || len(state.Allies) != 1 || len(state.Enemies) != 2 {
		t.Fatalf("unexpected slice lengths: %+v", state)
	}

	// Caso Blind Pick sin bans ni enemigos (null -> slice vacío, draft_phase -> first_pick)
	rawEmpty := `{"role":"ADC","bans":null,"allies":[],"enemies":null}`
	emptyState, err := parseDraftVisionJSON(rawEmpty)
	if err != nil {
		t.Fatalf("unexpected error on empty state: %v", err)
	}
	if emptyState.Role != "Dragon" {
		t.Fatalf("expected Dragon, got %s", emptyState.Role)
	}
	if emptyState.DraftPhase != "first_pick" {
		t.Fatalf("expected first_pick, got %s", emptyState.DraftPhase)
	}
	if emptyState.Bans == nil || emptyState.Enemies == nil {
		t.Fatalf("expected non-nil empty slices: %+v", emptyState.Bans)
	}

	// Caso 2da foto con campeón propio ya seleccionado (full_locked) + fallback de rol
	rawLocked := `{"role":"Auto","my_pick":"Ahri","bans":["Zed"],"allies":["Malphite","Lee Sin","Jinx","Lulu"],"enemies":["Orianna","Vi","Darius","Ezreal","Nami"]}`
	lockedState, err := parseDraftVisionJSON(rawLocked, "Mid")
	if err != nil {
		t.Fatalf("unexpected error on locked state: %v", err)
	}
	if lockedState.Role != "Mid" || lockedState.DraftPhase != "full_locked" || lockedState.MyPick != "Ahri" {
		t.Fatalf("unexpected locked state: %+v", lockedState)
	}
}
