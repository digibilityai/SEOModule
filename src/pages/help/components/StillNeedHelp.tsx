import { Link } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

export function StillNeedHelp() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Still need help?</CardTitle>
        <CardDescription>
          If this didn't answer your question, our support team can help. Signing in may be
          required to open a support request.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Button asChild>
          <Link to="/seo/support">Contact Support</Link>
        </Button>
      </CardContent>
    </Card>
  );
}
