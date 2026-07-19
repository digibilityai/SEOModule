import { Link } from "react-router-dom";
import type { RecommendedNextStep } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface RecommendedNextStepCardProps {
  step: RecommendedNextStep;
}

export function RecommendedNextStepCard({ step }: RecommendedNextStepCardProps) {
  return (
    <Card className="border-primary/40 bg-primary/5">
      <CardHeader>
        <CardTitle className="text-base">Recommended next step</CardTitle>
        <CardDescription>{step.description}</CardDescription>
      </CardHeader>
      <CardContent>
        {step.route ? (
          <Button asChild>
            <Link to={step.route}>{step.label}</Link>
          </Button>
        ) : (
          <Button disabled title="Coming soon">
            {step.label} (coming soon)
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
