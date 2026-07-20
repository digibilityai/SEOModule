// Client-side search box. No network request; the query is never persisted
// (no localStorage/analytics) and never logged. Submitting navigates to
// /help/search?q=... ; the search route itself does the actual matching.
import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export function HelpSearchBox({
  initialQuery = "",
  autoFocus = false,
  placeholder = "Search the Help Center…",
}: {
  initialQuery?: string;
  autoFocus?: boolean;
  placeholder?: string;
}) {
  const [value, setValue] = useState(initialQuery);
  const navigate = useNavigate();

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    const q = value.trim();
    navigate(q ? `/help/search?q=${encodeURIComponent(q)}` : "/help/search");
  };

  return (
    <form onSubmit={onSubmit} role="search" aria-label="Help Center search" className="flex w-full max-w-xl gap-2">
      <label htmlFor="help-search-input" className="sr-only">
        Search the Help Center
      </label>
      <Input
        id="help-search-input"
        type="search"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder={placeholder}
        autoFocus={autoFocus}
        className="h-11 text-base"
      />
      <Button type="submit" className="h-11">
        Search
      </Button>
    </form>
  );
}
