/// The browser only waits for a native decision; it cannot approve a connection.
enum ApprovalPage {
  static func expired(nonce: String) -> String {
    """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Connection request ended</title>
    <style nonce="\(nonce)">
      :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
      body { max-width: 480px; margin: 12vh auto; padding: 32px; line-height: 1.5; }
      h1 { font-size: 24px; }
    </style></head><body><h1>Connection request ended</h1>
    <p>This request expired or has already been completed. Start login again in your client if you still need to connect.</p>
    </body></html>
    """
  }

  static func html(id: String, nonce: String) -> String {
    // Both values are generated base64url strings. No client labels, state, or codes enter HTML.
    """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Approve in iMCP-HTTP</title>
    <style nonce="\(nonce)">
      :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
      body { margin: 0; padding: 32px; }
      main { max-width: 480px; margin: 12vh auto; }
      h1 { font-size: 24px; } p { line-height: 1.5; }
      button { font: inherit; padding: 6px 12px; cursor: pointer; }
    </style></head><body>
    <main id="approval" data-url="/approval?id=\(id)">
      <h1>Approve in iMCP-HTTP</h1>
      <p>Open Connections in iMCP-HTTP or its menu-bar panel. Choose Approve, then authenticate with macOS.</p>
      <p id="status" role="status">Waiting for your decision. This request expires after three minutes.</p>
      <button id="retry" hidden>Check again</button>
      <noscript><p>After your decision, <a href="/approval?id=\(id)">continue to your client</a>.</p></noscript>
    </main>
    <script nonce="\(nonce)">\(script)</script>
    </body></html>
    """
  }

  static let script = """
    const approvalURL = document.getElementById('approval').dataset.url;
    const status = document.getElementById('status');
    const retry = document.getElementById('retry');
    const waiting = status.textContent;
    let checking = false;
    let finished = false;
    let timer;
    function show(message) {
      if (status.textContent !== message) status.textContent = message;
    }
    async function check() {
      if (checking || finished) return;
      checking = true;
      clearTimeout(timer);
      retry.hidden = true;
      try {
        const response = await fetch(approvalURL.replace('/approval?', '/approval/status?'), {
          cache: 'no-store', credentials: 'omit', redirect: 'error',
          signal: AbortSignal.timeout(5000)
        });
        if (response.status === 400) {
          finished = true;
          show('This request expired or was closed. Start login again in your client.');
          return;
        }
        if (!response.ok) throw new Error('unavailable');
        const result = await response.json();
        if (result.ready === true) {
          finished = true;
          show('Returning to your client…');
          window.location.replace(approvalURL);
        } else if (result.ready === false) {
          show(waiting);
          timer = setTimeout(check, 1000);
        } else {
          throw new Error('invalid response');
        }
      } catch {
        show('Cannot reach iMCP-HTTP. Make sure the app is running, then check again.');
        retry.hidden = false;
      } finally {
        checking = false;
      }
    }
    retry.addEventListener('click', check);
    check();
    """
}
