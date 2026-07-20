import { jsPDF } from "jspdf";
import type { ProgressReport, SeoWebsite } from "@/types";

// Reports Stage 3 — client-side PDF rendering of the already-persisted report.
// Read-only: it renders exactly the stored ProgressReport (no regeneration, no
// recomputation). Unavailable areas (data_provenance === "unavailable") render
// "Not connected" and are never fabricated.
export const REPORT_PDF_VERSION = "1.0";

const MARGIN = 48;
const LINE = 16;

function isUnavailable(report: ProgressReport, area: string): boolean {
  return report.data_provenance?.[area] === "unavailable";
}

interface Section {
  title: string;
  area?: string; // provenance key; when unavailable -> "Not connected"
  lines: string[];
}

function buildSections(report: ProgressReport): Section[] {
  return [
    {
      title: "Executive Summary",
      lines: [
        report.overall_score_movement > 0
          ? `Overall visibility score is up ${report.overall_score_movement} points (${report.overall_score_previous} to ${report.overall_score_current}).`
          : report.overall_score_movement < 0
            ? `Overall visibility score is down ${Math.abs(report.overall_score_movement)} points (${report.overall_score_previous} to ${report.overall_score_current}).`
            : `Overall visibility score is steady at ${report.overall_score_current}.`,
        `${report.pending_approvals_count} item(s) awaiting approval; ${report.issues_fixed_count} fixed this period.`,
      ],
    },
    { title: "Technical Health", area: "audit", lines: [report.technical_summary, `Issues found: ${report.issues_found_count}. Fixed: ${report.issues_fixed_count}.`] },
    { title: "Content", area: "content", lines: [report.content_summary, `Planned: ${report.content_pieces_planned}. Completed: ${report.content_pieces_completed}.`] },
    { title: "Page Performance", area: "page_performance", lines: [report.performance_summary, `Improving: ${report.improving_pages_count}. Declining: ${report.declining_pages_count}.`] },
    { title: "Authority", area: "authority", lines: [report.offpage_summary, `Opportunities: ${report.authority_opportunities_count}.`] },
    { title: "AI Visibility", area: "ai_visibility", lines: [report.ai_visibility_summary, `Content gaps: ${report.ai_content_gaps_count}.`] },
    { title: "Competitor", area: "competitor", lines: [report.competitor_summary, `Gaps: ${report.competitor_gaps_count}.`] },
    { title: "Roadmap", area: "roadmap", lines: [report.roadmap_summary, `Completed: ${report.roadmap_completed_count} of ${report.roadmap_total_count}.`] },
    { title: "Expert Support", area: "expert_support", lines: [report.expert_support_summary, `Open requests: ${report.open_support_requests_count}.`] },
    { title: "Next Actions", lines: report.next_actions.length > 0 ? report.next_actions.map((a) => `- ${a}`) : ["- No urgent actions right now."] },
  ];
}

function sanitize(value: string): string {
  return value.replace(/[^a-z0-9]+/gi, "-").replace(/^-+|-+$/g, "").toLowerCase();
}

export function reportPdfFilename(report: ProgressReport, website: SeoWebsite): string {
  return `digibility-seo-report-${sanitize(website.name || website.website_url)}-${sanitize(report.period_label)}.pdf`;
}

/** Renders the stored report to a PDF and triggers a browser download. */
export function downloadReportPdf(report: ProgressReport, website: SeoWebsite): void {
  const doc = new jsPDF({ unit: "pt", format: "a4" });
  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();
  const contentWidth = pageWidth - MARGIN * 2;
  const generatedAt = new Date(report.generated_at).toLocaleString();
  const reportTitle = `Progress report — ${report.period_label}`;

  doc.setProperties({
    title: `${reportTitle} — ${website.name}`,
    subject: "Digibility SEO Progress Report",
    author: "Digibility",
    creator: `Digibility SEO (report v${REPORT_PDF_VERSION})`,
    keywords: `seo, report, ${report.period_key}`,
  });

  let y = MARGIN;
  const ensureSpace = (needed: number) => {
    if (y + needed > pageHeight - MARGIN) {
      doc.addPage();
      y = MARGIN;
    }
  };
  const writeLines = (text: string, size: number, style: "normal" | "bold" = "normal") => {
    doc.setFont("helvetica", style);
    doc.setFontSize(size);
    for (const line of doc.splitTextToSize(text, contentWidth) as string[]) {
      ensureSpace(LINE);
      doc.text(line, MARGIN, y);
      y += LINE;
    }
  };

  // Header
  writeLines(reportTitle, 18, "bold");
  writeLines(website.name, 12, "bold");
  writeLines(website.website_url, 10);
  writeLines(`Reporting period: ${report.period_label} (${report.period_start} to ${report.period_end})`, 10);
  writeLines(`Generated: ${generatedAt}`, 10);
  y += LINE / 2;

  for (const section of buildSections(report)) {
    ensureSpace(LINE * 2);
    y += LINE / 2;
    writeLines(section.title, 13, "bold");
    if (section.area && isUnavailable(report, section.area)) {
      writeLines("Not connected", 10);
    } else {
      for (const line of section.lines) {
        if (line) writeLines(line, 10);
      }
    }
  }

  // Footer on every page
  const pages = doc.getNumberOfPages();
  for (let p = 1; p <= pages; p++) {
    doc.setPage(p);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8);
    doc.setTextColor(120);
    doc.text(
      `Generated by Digibility · ${generatedAt} · Report v${REPORT_PDF_VERSION} · Page ${p} of ${pages}`,
      MARGIN,
      pageHeight - MARGIN / 2,
    );
    doc.setTextColor(0);
  }

  doc.save(reportPdfFilename(report, website));
}
