import { getModuleById } from "@/registry/moduleRegistry";
import { Badge } from "@/components/ui/badge";
import { PlaceholderPage } from "./PlaceholderPage";

interface ModulePlaceholderPageProps {
  moduleId: string;
}

export function ModulePlaceholderPage({ moduleId }: ModulePlaceholderPageProps) {
  const module = getModuleById(moduleId);

  if (!module) {
    return (
      <PlaceholderPage
        title="Unknown module"
        description={`No module registered with id "${moduleId}".`}
      />
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Badge variant="secondary">{module.status}</Badge>
        {module.planAvailability.map((plan) => (
          <Badge key={plan} variant="outline">
            {plan}
          </Badge>
        ))}
      </div>
      <PlaceholderPage title={module.name} description={module.shortDescription} />
    </div>
  );
}
