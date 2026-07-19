import { MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const NOTES_KEY = "admin_notes";

interface AdminNote {
  website_id: string;
  note: string;
  updated_at: string;
}

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Admin-only data with no equivalent in the customer-facing app — internal
// notes the Digibility team keeps about a client site.
const seedNotes: AdminNote[] = [
  {
    website_id: siteA.id,
    note: "Standard plan, active client. No blockers — reviewing review-request cadence with the client next check-in.",
    updated_at: "2026-07-06T09:00:00.000Z",
  },
];

export const mockAdminNotes: AdminNote[] = loadMockCollection(NOTES_KEY, seedNotes);

function persist(): void {
  saveMockCollection(NOTES_KEY, mockAdminNotes);
}

export function getAdminNote(websiteId: string): string {
  return mockAdminNotes.find((n) => n.website_id === websiteId)?.note ?? "";
}

export function setAdminNote(websiteId: string, note: string): void {
  const index = mockAdminNotes.findIndex((n) => n.website_id === websiteId);
  const entry: AdminNote = { website_id: websiteId, note, updated_at: new Date().toISOString() };
  if (index === -1) {
    mockAdminNotes.push(entry);
  } else {
    mockAdminNotes[index] = entry;
  }
  persist();
}
