package handlers_test

import (
	"backend/internal/handlers"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGetEcosystemOverviewWithoutDB(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/ecosystem/overview", nil)
	rec := httptest.NewRecorder()

	handlers.GetEcosystemOverview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "active_players") || !strings.Contains(body, "484") {
		t.Errorf("expected overview JSON to contain active_players >= 484, got %s", body)
	}
}

func TestGetTournamentInfoWithoutDB(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/ecosystem/tournament/info", nil)
	rec := httptest.NewRecorder()

	handlers.GetTournamentInfo(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "Copa Latino Americana") || !strings.Contains(body, "Domingo 6 de Diciembre") {
		t.Errorf("expected tournament JSON to include C.L.A schedule, got %s", body)
	}
}

func TestGetCommunityPollsWithoutDB(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/ecosystem/community/polls", nil)
	rec := httptest.NewRecorder()

	handlers.GetCommunityPolls(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "tournament_scrim_mode") || !strings.Contains(body, "match_history_builds") {
		t.Errorf("expected community polls JSON to include default options, got %s", body)
	}
}

