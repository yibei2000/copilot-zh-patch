/*
 * GitHub Copilot 中文补丁 — 运行时翻译引擎（注入到 WebView 页面中执行）
 * Runtime UI translation engine for the GitHub Copilot desktop app (Tauri/WebView2).
 *
 * 设计原则:
 *  - 只在“精确命中词典”时替换文本，绝不猜测，未命中保留英文。
 *  - 跳过代码/输入框/编辑器/聊天正文等用户内容区域，避免改坏用户数据。
 *  - MutationObserver 增量处理，兼容 React 重渲染与 SPA 路由切换。
 */
(() => {
  'use strict';

  const BUILD_ID = /*__ZH_BUILD_ID__*/ '';
  const DICT = /*__ZH_DICT__*/ {};
  // [[source, flags, template], ...] —— 运行时编译，便于从 JSON 载入
  const PATTERNS = (/*__ZH_PATTERNS__*/ []).map(([src, flags, tpl]) => [new RegExp(src, flags), tpl]);

  if (window.__copilotZh && window.__copilotZh.version === BUILD_ID) {
    window.__copilotZh.rescan();
    return window.__copilotZh.version;
  }
  if (window.__copilotZh && typeof window.__copilotZh.dispose === 'function') {
    try { window.__copilotZh.dispose(); } catch (e) { /* 忽略旧版本清理异常 */ }
  }

  const ATTRS = ['placeholder', 'aria-label', 'title', 'alt'];
  const SKIP_SELECTOR = [
    'pre',
    'code',
    'kbd',
    'samp',
    'var',
    'textarea',
    'input',
    'select',
    '[contenteditable=""]',
    '[contenteditable="true"]',
    '[contenteditable="plaintext-only"]',
    '.monaco-editor',
    '.monaco-diff-editor',
    '.xterm',
    '[data-copilot-zh-skip]',
    '[class*="markdown"]',
    '[data-testid*="markdown"]',
    '[data-testid*="diff"]',
    '[class*="diff-"]',
    '[class*="prose"]',
  ].join(',');

  const stats = { translatedNodes: 0, translatedAttrs: 0, patterns: 0, missingAdded: 0 };
  const missing = new Map(); // english -> count (visible, not translated)
  const marked = new WeakMap();

  const SKIP_SELECTOR_ATTR = [
    'pre',
    'code',
    'kbd',
    'samp',
    'var',
    '.monaco-editor',
    '.monaco-diff-editor',
    '.xterm',
    '[data-copilot-zh-skip]',
  ].join(',');

  function isSkipped(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el.closest(SKIP_SELECTOR)) return true;
    return false;
  }

  // 输入框自身的 placeholder/title 需要翻译，所以属性检查放宽一档
  function isSkippedAttr(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el.closest(SKIP_SELECTOR_ATTR)) return true;
    return false;
  }

  function visible(el) {
    if (!el || el.nodeType !== 1) return false;
    if (!el.getClientRects().length) return false;
    const cs = getComputedStyle(el);
    return cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0';
  }

  /** 判断一段文本是否“像界面文案”，用于收集未翻译字符串 */
  function looksLikeUi(s) {
    if (!s || s.length < 2 || s.length > 120) return false;
    if (!/[A-Za-z]{2}/.test(s)) return false;
    if (!/^[A-Z0-9"'“(\[]/.test(s) && !/\s/.test(s)) return false;
    if (/^[a-z0-9]+(?:[-_.:/][a-z0-9]+)+$/i.test(s)) return false; // token / path
    if (/https?:\/\/|www\./.test(s)) return false;
    if (/[{}=<>;\\`]/.test(s)) return false;
    if (/^[a-z]+(?:[A-Z][a-z]+)+$/.test(s)) return false; // camelCase
    return true;
  }

  const MONTHS = {
    January: 1, February: 2, March: 3, April: 4, May: 5, June: 6,
    July: 7, August: 8, September: 9, October: 10, November: 11, December: 12,
  };
  const EN_DATE = /(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s+(\d{4})(?:,?\s+at\s+(\d{1,2}):(\d{2})\s*(AM|PM))?/g;

  /** 把英文日期（如 October 31, 2026, at 11:43 PM）转成中文写法 */
  function localizeDates(text) {
    let changed = false;
    const out = text.replace(EN_DATE, (_m, month, day, year, hour, minute, ampm) => {
      changed = true;
      let result = `${year}年${MONTHS[month]}月${day}日`;
      if (hour != null) {
        let h = Number(hour) % 12;
        if (ampm === 'PM') h += 12;
        result += ` ${String(h).padStart(2, '0')}:${minute}`;
      }
      return result;
    });
    return changed ? out : null;
  }

  function specialTranslations(text) {
    const m = /^Up to date\. Last checked on (.+)\.$/.exec(text);
    if (m) {
      const when = localizeDates(m[1]) || m[1];
      stats.patterns++;
      return `已是最新版本。上次检查：${when}。`;
    }
    const dates = localizeDates(text);
    if (dates) {
      stats.patterns++;
      return dates;
    }
    return null;
  }

  function lookup(text) {
    if (!text) return null;
    const exact = DICT[text];
    if (typeof exact === 'string') return exact;
    for (let i = 0; i < PATTERNS.length; i++) {
      const [re, fn] = PATTERNS[i];
      const m = re.exec(text);
      if (m) {
        const out = typeof fn === 'function' ? fn(m) : fn.replace(/\$(\d)/g, (_, d) => m[+d] ?? '');
        if (typeof out === 'string') {
          stats.patterns++;
          return out;
        }
      }
    }
    return specialTranslations(text);
  }

  function translateTextNode(node) {
    const parent = node.parentElement;
    if (!parent) return;
    if (isSkipped(parent)) return;
    const raw = node.nodeValue;
    if (!raw) return;
    const text = raw.trim();
    if (!text || !/[A-Za-z]/.test(text)) return;

    const mark = marked.get(node);
    if (mark && raw === mark.zh) return;

    const zh = lookup(text);
    if (zh == null) {
      if (mark && raw !== mark.en) marked.delete(node);
      if (visible(parent) && looksLikeUi(text)) {
        if (!missing.has(text)) stats.missingAdded++;
        missing.set(text, (missing.get(text) || 0) + 1);
      }
      return;
    }
    const lead = /^\s*/.exec(raw)[0];
    const trail = /\s*$/.exec(raw)[0];
    const next = lead + zh + trail;
    if (next === raw) return;
    node.nodeValue = next;
    marked.set(node, { en: text, zh: next });
    stats.translatedNodes++;
  }

  function translateAttr(el, name) {
    if (isSkippedAttr(el)) return;
    const raw = el.getAttribute(name);
    if (!raw) return;
    const text = raw.trim();
    if (!text || !/[A-Za-z]/.test(text)) return;
    const zh = lookup(text);
    if (zh == null) return;
    if (zh === text) return;
    el.setAttribute(name, zh);
    stats.translatedAttrs++;
  }

  const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, null);

  function translateSubtree(root) {
    if (!root) return;
    if (root.nodeType === 3) {
      translateTextNode(root);
      return;
    }
    if (root.nodeType !== 1) return;
    // 属性（aria-label / placeholder / title / alt）
    for (const a of ATTRS) if (root.hasAttribute(a)) translateAttr(root, a);
    for (const el of root.querySelectorAll('[aria-label],[placeholder],[title],[alt]')) {
      for (const a of ATTRS) if (el.hasAttribute(a)) translateAttr(el, a);
    }
    // 文本
    const tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    let n = tw.nextNode();
    while (n) {
      translateTextNode(n);
      n = tw.nextNode();
    }
    // 语言 / 标题
    if (document.documentElement.lang !== 'zh-CN') document.documentElement.lang = 'zh-CN';
    const t = document.title;
    if (t) {
      const zt = lookup(t.trim());
      if (zt) document.title = zt;
    }
  }

  let timer = null;
  const pending = new Set();
  function schedule(root) {
    pending.add(root);
    if (timer) return;
    timer = requestAnimationFrame(() => {
      timer = null;
      const roots = [...pending];
      pending.clear();
      for (const r of roots) {
        try {
          if (r && r.isConnected) translateSubtree(r);
        } catch (e) {
          /* 忽略单个节点异常 */
        }
      }
    });
  }

  const observer = new MutationObserver((records) => {
    for (const rec of records) {
      if (rec.type === 'childList') {
        for (const n of rec.addedNodes) {
          if (n.nodeType === 3) schedule(n.parentElement || n);
          else if (n.nodeType === 1) schedule(n);
        }
      } else if (rec.type === 'characterData') {
        schedule(rec.target.parentElement || rec.target);
      } else if (rec.type === 'attributes') {
        if (rec.target && rec.target.nodeType === 1) translateAttr(rec.target, rec.attributeName);
      }
    }
  });

  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    characterData: true,
    attributes: true,
    attributeFilter: ATTRS,
  });

  translateSubtree(document.body || document.documentElement);

  window.__copilotZh = {
    version: BUILD_ID,
    stats,
    dispose() {
      try { observer.disconnect(); } catch (e) { /* 忽略 */ }
      if (timer) { cancelAnimationFrame(timer); timer = null; }
      pending.clear();
    },
    rescan() {
      missing.clear();
      translateSubtree(document.body || document.documentElement);
    },
    takeMissing() {
      const out = [...missing.entries()].sort((a, b) => b[1] - a[1]).map(([en, n]) => ({ en, n }));
      missing.clear();
      return out;
    },
    setEnabled(on) {
      if (on) {
        observer.takeRecords();
        translateSubtree(document.body);
      } else {
        observer.disconnect();
      }
    },
  };
  return 'copilot-zh installed: ' + Object.keys(DICT).length + ' entries';
})();
