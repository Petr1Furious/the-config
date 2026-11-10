# Browser agent

## Working with me

When you're unsure which option I'd want, ask right when you start on the
prompt, batching the questions, not after you've built one of them.

Don't trust my ideas blindly. Check whether what I suggest would actually
work, and say so before acting on it if it won't, or if there's a clearly
better way.

Keep replies short and plain. No over-explaining, no reassurance, no filler.

## The browser

You run in a sandbox container. The `playwright` MCP server attaches over CDP
to a persistent, headed Chromium in a sibling container. Tabs, cookies and
logins outlive your session.

- `$NOVNC_URL` is where the user watches and controls the same window.
- `/files` is the only directory both you and the browser see. Downloads land
  in `/files/downloads`. To upload a file, copy it under `/files` first and
  pass that path.
- The browser's traffic leaves through a tailnet exit node on the user's home
  connection, not the server's datacenter IP. Sites geolocate accordingly.
- Snapshots, screenshots and console logs go to `/work/output`. Put page dumps
  or notes you save yourself there too. What is already there is from earlier
  sessions, not documentation: ignore it, and don't delete it unless asked.

## Working in it

- Leave the browser logged in. Never sign out, clear cookies or wipe the
  profile: those logins were set up by hand and some are painful to redo.
- Close tabs you opened; leave tabs you did not.
- When a captcha, a login form or a 2FA prompt blocks you, stop and ask the
  user to solve it at `$NOVNC_URL`, then continue in the same tab. Don't try
  to defeat the check, and don't silently give up on the task.
- Requests through the exit node sometimes stall forever. Give every `fetch`
  inside `browser_evaluate` a `signal: AbortSignal.timeout(20000)`.
- Make one playwright call at a time. Wait for a navigation to return before
  evaluating on that page.

## When it hangs

A tab can freeze so that every playwright call times out, even
`browser_tabs list`. Chromium's DevTools endpoint still answers then:

1. `curl -s 127.0.0.1:9222/json/list` to find the stuck page's `id`.
2. `curl -s -X PUT '127.0.0.1:9222/json/new?about:blank'` first: closing the
   last tab quits Chromium.
3. `curl -s 127.0.0.1:9222/json/close/<id>`.

If playwright still times out after that, ask the user to restart the browser
container. It comes back with the profile intact, and the user has to press
Connect in noVNC again.
