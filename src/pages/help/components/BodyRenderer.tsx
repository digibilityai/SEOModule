// Renders structured HelpBodyBlock[] safely. No dangerouslySetInnerHTML, no
// raw HTML, no runtime markdown parsing — every block type is an explicit,
// known React element.
import { Link } from "react-router-dom";
import type { HelpBodyBlock } from "@/help/types";

function BlockRenderer({ block }: { block: HelpBodyBlock }) {
  switch (block.type) {
    case "paragraph":
      return <p className="text-sm leading-relaxed text-foreground">{block.text}</p>;
    case "heading":
      return (
        <h2 id={block.id} className="scroll-mt-20 text-lg font-semibold text-foreground">
          {block.text}
        </h2>
      );
    case "steps":
      return (
        <ol className="list-decimal space-y-1 pl-5 text-sm text-foreground">
          {block.items.map((item, i) => (
            <li key={i}>{item}</li>
          ))}
        </ol>
      );
    case "list":
      return (
        <ul className="list-disc space-y-1 pl-5 text-sm text-foreground">
          {block.items.map((item, i) => (
            <li key={i}>{item}</li>
          ))}
        </ul>
      );
    case "callout":
      return (
        <div className="rounded-md border border-border bg-muted/40 p-3 text-sm text-foreground">
          {block.text}
        </div>
      );
    case "warning":
      return (
        <div role="alert" className="rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm text-foreground">
          <strong className="font-medium">Important: </strong>
          {block.text}
        </div>
      );
    case "statusNotice":
      return (
        <div className="rounded-md border border-border bg-secondary/40 p-3 text-sm text-foreground">
          {block.text}
        </div>
      );
    case "definition":
      return (
        <dl className="text-sm text-foreground">
          <dt className="font-medium">{block.term}</dt>
          <dd className="mt-1 text-muted-foreground">{block.text}</dd>
        </dl>
      );
    case "table":
      return (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-border text-left">
                {block.headers.map((h, i) => (
                  <th key={i} className="py-2 pr-4 font-medium text-foreground">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {block.rows.map((row, i) => (
                <tr key={i} className="border-b border-border/60">
                  {row.map((cell, j) => (
                    <td key={j} className="py-2 pr-4 text-muted-foreground">
                      {cell}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    case "relatedLink":
      return (
        <Link
          to={`/help/article/${block.articleSlug}`}
          className="block text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-2"
        >
          {block.label} →
        </Link>
      );
    case "expectedResult":
      return (
        <div className="rounded-md border border-border p-3 text-sm text-foreground">
          <strong className="font-medium">Expected result: </strong>
          {block.text}
        </div>
      );
    case "troubleshootingNote":
      return (
        <div className="rounded-md border border-border p-3 text-sm text-foreground">
          <strong className="font-medium">If this doesn't work: </strong>
          {block.text}
        </div>
      );
    case "escalationNote":
      return (
        <div className="rounded-md border border-border p-3 text-sm text-foreground">
          <strong className="font-medium">Still stuck? </strong>
          {block.text}
        </div>
      );
    default:
      return null;
  }
}

export function BodyRenderer({ blocks }: { blocks: HelpBodyBlock[] }) {
  return (
    <div className="space-y-4">
      {blocks.map((block, i) => (
        <BlockRenderer key={i} block={block} />
      ))}
    </div>
  );
}
