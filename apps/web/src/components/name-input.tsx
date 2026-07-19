import { Input } from "@/components/ui/input";
import { slugify } from "@/lib/api";

/**
 * Inline naming field: Enter submits the slugified value, Escape or blur
 * cancels. Whatever the user types becomes a lowercase-dashes name.
 */
export function NameInput({
  placeholder,
  initial,
  onSubmit,
  onCancel,
  className,
}: {
  placeholder: string;
  initial?: string;
  onSubmit: (slug: string) => void;
  onCancel: () => void;
  className?: string;
}) {
  return (
    <Input
      autoFocus
      defaultValue={initial}
      placeholder={placeholder}
      className={className}
      onFocus={(e) => e.currentTarget.select()}
      onBlur={onCancel}
      onKeyDown={(e) => {
        if (e.key === "Escape") onCancel();
        if (e.key === "Enter") {
          const slug = slugify(e.currentTarget.value);
          if (slug) onSubmit(slug);
        }
      }}
    />
  );
}
