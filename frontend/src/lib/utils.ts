import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}


export function generateSlug(title: string) {
  return title
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
}


const FALLBACK_IMAGE =
  "https://images.unsplash.com/photo-1511285605577-4d62fb50d2f7?fm=jpg&q=60&w=3000&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MjB8fHBsYWNlaG9sZGVyfGVufDB8fDB8fHww";

// The backend stores only a bare filename in a post's `image` field and serves
// the file at `/images/posts/<filename>`. We build a browser-facing URL here.
// By default the URL is RELATIVE so it resolves against whatever origin served
// the page (gateway / tunnel / real domain) — set NEXT_PUBLIC_IMAGE_BASE_URL
// only when the backend lives on a different origin than the frontend.
export function getImageUrlFromPath(path: string | null) {
  if (!path) return FALLBACK_IMAGE;
  // Already an absolute URL (legacy data) — use as-is.
  if (/^https?:\/\//i.test(path)) return path;
  // Already a rooted images path — don't prefix it twice.
  if (path.startsWith("/images/")) return path;

  const baseUrl = process.env.NEXT_PUBLIC_IMAGE_BASE_URL ?? "";
  const file = path.replace(/^\/+/, "");
  return `${baseUrl}/images/posts/${file}`;
}

export function formatDate(utcString: string): string {
  const date = new Date(utcString);
 
  if (isNaN(date.getTime())) return 'Invalid date';
 
  return date.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
}
 