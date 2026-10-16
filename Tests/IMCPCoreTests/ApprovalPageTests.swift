import JavaScriptCore
import Testing

@testable import IMCPCore

@MainActor
struct ApprovalPageTests {
  @Test func waitsWithoutNavigationOrOverlappingRequestsThenReturnsOnce() throws {
    let js = try harness()
    #expect(js.evaluateScript("requests.length")?.toInt32() == 1)
    js.evaluateScript("check(); check();")
    #expect(js.evaluateScript("requests.length")?.toInt32() == 1)
    js.evaluateScript("answer(200, {ready: false});")
    #expect(js.evaluateScript("navigations.length")?.toInt32() == 0)
    #expect(js.evaluateScript("nodes.status.writes")?.toInt32() == 0)
    #expect(js.evaluateScript("timers.size")?.toInt32() == 1)
    js.evaluateScript("tick(); answer(200, {ready: true}); check(); retryAction();")
    #expect(js.evaluateScript("navigations.length")?.toInt32() == 1)
    #expect(js.evaluateScript("navigations[0]")?.toString() == "/approval?id=fixture")
    #expect(js.evaluateScript("timers.size")?.toInt32() == 0)
    #expect(js.exception == nil)
  }

  @Test func failuresStopPollingAndRetryChecksTheSameRequest() throws {
    let js = try harness()
    js.evaluateScript("rejectFetch(new Error('offline')); ")
    #expect(js.evaluateScript("nodes.retry.hidden")?.toBool() == false)
    #expect(js.evaluateScript("timers.size")?.toInt32() == 0)
    js.evaluateScript("retryAction(); retryAction();")
    #expect(js.evaluateScript("requests.length")?.toInt32() == 2)
    #expect(
      js.evaluateScript("requests.every(url => url === '/approval/status?id=fixture')")?.toBool()
        == true)
    js.evaluateScript("answer(200, {ready: false});")
    #expect(js.evaluateScript("nodes.retry.hidden")?.toBool() == true)
    #expect(js.evaluateScript("nodes.status.textContent")?.toString() == "Waiting")
    #expect(js.evaluateScript("navigations.length")?.toInt32() == 0)
    #expect(js.exception == nil)
  }

  @Test func expiredRequestStopsWithoutCreatingAnotherLogin() throws {
    let js = try harness()
    js.evaluateScript("answer(400, {error: 'expired_request'}); check(); retryAction();")
    #expect(js.evaluateScript("requests.length")?.toInt32() == 1)
    #expect(js.evaluateScript("timers.size")?.toInt32() == 0)
    #expect(js.evaluateScript("navigations.length")?.toInt32() == 0)
    #expect(
      js.evaluateScript("nodes.status.textContent.includes('Start login again')")?.toBool() == true)
    #expect(js.exception == nil)
  }

  private func harness() throws -> JSContext {
    let js = try #require(JSContext())
    js.evaluateScript(
      """
      const requests = [], navigations = [], timers = new Map();
      let resolveFetch, rejectFetch, retryAction, timerID = 0;
      const nodes = {
        approval: {dataset: {url: '/approval?id=fixture'}},
        status: {value: 'Waiting', writes: 0,
          get textContent() { return this.value; },
          set textContent(value) { this.writes++; this.value = value; }},
        retry: {hidden: true, addEventListener(event, action) { retryAction = action; }}
      };
      const document = {getElementById(id) { return nodes[id]; }};
      const window = {location: {replace(url) { navigations.push(url); }}};
      const AbortSignal = {timeout() { return {}; }};
      function fetch(url) {
        requests.push(url);
        return new Promise((resolve, reject) => { resolveFetch = resolve; rejectFetch = reject; });
      }
      function answer(status, body) {
        resolveFetch({status, ok: status === 200, json: async () => body});
      }
      function setTimeout(action) { timers.set(++timerID, action); return timerID; }
      function clearTimeout(id) { timers.delete(id); }
      function tick() { const [id, action] = timers.entries().next().value; timers.delete(id); action(); }
      """)
    js.evaluateScript(ApprovalPage.script)
    try #require(js.exception == nil)
    return js
  }
}
