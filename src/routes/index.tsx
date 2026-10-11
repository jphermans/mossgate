import { createFileRoute } from "@tanstack/react-router";
import { Mossgate } from "@/components/mossgate";

export const Route = createFileRoute("/")({
  component: Home,
});

function Home() {
  return <Mossgate />;
}
