export function sectionHeading(line) {
  const markdown = line.match(/^\s{0,3}#{1,6}\s+(.+)$/);
  if (markdown) return {title: markdown[1].trim(), includeInContent: false};
  const title = line.trim();
  if (title.length > 140 || /\.{3,}|[.!?;)]$/.test(title)) return null;
  if (/^\d+(?:\.\d+){0,5}[.)]?\s+[A-ZА-ЯЁ]/.test(title) ||
      /^(?:Глава|Раздел|Chapter|Section)\s+(?:\d+|[IVXLCDM]+)(?:\s|$)/.test(title)) {
    return {title, includeInContent: true};
  }
  return null;
}
