import { Bold, Code, Heading, Italic, Link, List, ListOrdered, Strikethrough } from "lucide-react";
import type { EditorView } from "@codemirror/view";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { cycleHeading, insertLink, toggleLinePrefix, toggleOrderedList, toggleWrap } from "@/lib/markdown-commands";

interface Item {
  label: string;
  icon: React.ReactNode;
  run: (view: EditorView) => boolean;
}

const GROUPS: Item[][] = [
  [
    { label: "Bold ⌘B", icon: <Bold />, run: (v) => toggleWrap(v, "**") },
    { label: "Italic ⌘I", icon: <Italic />, run: (v) => toggleWrap(v, "*") },
    { label: "Strikethrough", icon: <Strikethrough />, run: (v) => toggleWrap(v, "~~") },
  ],
  [
    { label: "Heading", icon: <Heading />, run: cycleHeading },
    { label: "Bullet list", icon: <List />, run: (v) => toggleLinePrefix(v, "- ") },
    { label: "Numbered list", icon: <ListOrdered />, run: toggleOrderedList },
  ],
  [
    { label: "Code", icon: <Code />, run: (v) => toggleWrap(v, "`") },
    { label: "Link", icon: <Link />, run: insertLink },
  ],
];

export function EditorToolbar({ getView }: { getView: () => EditorView | null }) {
  return (
    <TooltipProvider delayDuration={400}>
      <div className="flex items-center gap-0.5 border-b px-5 py-1.5">
        {GROUPS.map((group, i) => (
          <div key={i} className="flex items-center gap-0.5">
            {i > 0 && <div className="mx-1.5 h-4 w-px bg-border" />}
            {group.map((item) => (
              <Tooltip key={item.label}>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={item.label}
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => {
                      const view = getView();
                      if (view) item.run(view);
                    }}
                  >
                    {item.icon}
                  </Button>
                </TooltipTrigger>
                <TooltipContent side="bottom">{item.label}</TooltipContent>
              </Tooltip>
            ))}
          </div>
        ))}
      </div>
    </TooltipProvider>
  );
}
