export function projectFromLocation(location:Pick<Location,'hash'|'search'|'pathname'>):string {
 const hashQuery=location.hash.split('?')[1]||'';
 return new URLSearchParams(hashQuery).get('project')||new URLSearchParams(location.search).get('project')||decodeURIComponent(location.pathname.match(/^\/api\/([^/]+)\//)?.[1]||'');
}
