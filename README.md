# blog.rymcg.tech static redirects

This branch is a free static-host redirect shim for the retired
`blog.rymcg.tech` site.

Deploy this branch to a static host that supports Netlify-style `_redirects`,
such as Netlify or Cloudflare Pages. Requests receive real `301` redirects to
`https://book.rymcg.tech`.

Special cases:

- `/blog/license/` redirects to `/license/`.
- `/blog/page/1/` through `/blog/page/5/` redirect to `/blog/`.
- Every other path redirects to the same path on `book.rymcg.tech`.

