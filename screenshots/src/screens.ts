import { DeviceSpec } from './devices'

/** Returns the full HTML page for a given screen, sized to the device's logical viewport */
export function getScreenHTML(screenId: string, device: DeviceSpec): string {
  const isIPad = device.slug.startsWith('ipad')
  const isLegacy = device.cornerRadius === 0 // iPhone 8 Plus style
  const contentHeight = device.logicalHeight - device.statusBar - device.homeIndicator

  const base = `
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=${device.logicalWidth}, initial-scale=1.0">
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');

  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    width: ${device.logicalWidth}px;
    height: ${device.logicalHeight}px;
    overflow: hidden;
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif;
    -webkit-font-smoothing: antialiased;
    background: #FFFFFF;
  }

  :root {
    --green: #2ECC71;
    --green-dark: #22a85c;
    --green-light: #dcfce7;
    --green-50: #f0fdf4;
    --orange: #f97316;
    --red: #ef4444;
    --blue: #3b82f6;
    --gray-50: #f9fafb;
    --gray-100: #f3f4f6;
    --gray-200: #e5e7eb;
    --gray-300: #d1d5db;
    --gray-400: #9ca3af;
    --gray-500: #6b7280;
    --gray-600: #4b5563;
    --gray-700: #374151;
    --gray-800: #1f2937;
    --gray-900: #111827;
    --status-bar: ${device.statusBar}px;
    --home-indicator: ${device.homeIndicator}px;
    --corner-radius: ${device.cornerRadius}px;
  }

  .status-bar {
    height: var(--status-bar);
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    padding: 0 ${isLegacy ? '6' : '24'}px ${isLegacy ? '0' : '12'}px;
    font-size: ${isLegacy ? '12' : '15'}px;
    font-weight: 600;
    color: var(--gray-900);
  }
  .status-bar .time { font-weight: 700; font-size: ${isLegacy ? '12' : '16'}px; }
  .status-bar .icons { display: flex; gap: 5px; align-items: center; font-size: 12px; }

  .home-indicator-bar {
    height: var(--home-indicator);
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .home-indicator-pill {
    width: 134px;
    height: 5px;
    background: var(--gray-900);
    border-radius: 100px;
    opacity: 0.2;
  }

  .screen-content {
    height: ${contentHeight}px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  /* Tab bar */
  .tab-bar {
    display: flex;
    justify-content: space-around;
    align-items: center;
    padding: 8px 0 ${device.homeIndicator > 0 ? '0' : '8'}px;
    border-top: 0.5px solid var(--gray-200);
    background: rgba(249,250,251,0.95);
    backdrop-filter: blur(12px);
    flex-shrink: 0;
  }
  .tab-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    font-size: 10px;
    color: var(--gray-400);
  }
  .tab-item.active { color: var(--green); }
  .tab-item svg { width: 22px; height: 22px; }

  /* Nav bar */
  .nav-bar {
    padding: 8px 16px 12px;
    flex-shrink: 0;
  }
  .nav-bar h1 {
    font-size: ${isIPad ? '34' : '28'}px;
    font-weight: 700;
    color: var(--gray-900);
    letter-spacing: -0.5px;
  }

  /* Cards */
  .card {
    background: var(--gray-50);
    border-radius: 16px;
    padding: 16px;
    margin: 0 16px 12px;
  }
  .card-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--gray-500);
    text-transform: uppercase;
    letter-spacing: 0.3px;
    margin-bottom: 12px;
  }

  ${getScreenStyles(screenId, device)}
</style>
</head>
<body>
  ${getStatusBarHTML(device)}
  <div class="screen-content">
    ${getScreenContent(screenId, device)}
  </div>
  ${device.homeIndicator > 0 ? `<div class="home-indicator-bar"><div class="home-indicator-pill"></div></div>` : ''}
</body>
</html>`
  return base
}

function getStatusBarHTML(device: DeviceSpec): string {
  const isLegacy = device.cornerRadius === 0
  if (device.slug.startsWith('ipad')) {
    return `<div class="status-bar">
      <span class="time">9:41</span>
      <span class="icons">
        <svg width="16" height="12" viewBox="0 0 16 12"><path d="M1 5.5c2-3.5 12-3.5 14 0" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M4 8c1.5-2 6.5-2 8 0" stroke="currentColor" stroke-width="1.5" fill="none"/><circle cx="8" cy="10" r="1.5" fill="currentColor"/></svg>
        <svg width="24" height="12" viewBox="0 0 24 12"><rect x="0" y="1" width="20" height="10" rx="2" stroke="currentColor" stroke-width="1.2" fill="none"/><rect x="2" y="3" width="14" height="6" rx="1" fill="var(--green)"/><rect x="21" y="4" width="2" height="4" rx="1" fill="currentColor" opacity="0.3"/></svg>
      </span>
    </div>`
  }
  if (device.hasIsland) {
    return `<div class="status-bar" style="position:relative;">
      <span class="time">9:41</span>
      <div style="position:absolute;left:50%;top:${device.statusBar - 42}px;transform:translateX(-50%);width:126px;height:37px;background:var(--gray-900);border-radius:20px;"></div>
      <span class="icons">
        <svg width="16" height="12" viewBox="0 0 16 12"><path d="M1 5.5c2-3.5 12-3.5 14 0" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M4 8c1.5-2 6.5-2 8 0" stroke="currentColor" stroke-width="1.5" fill="none"/><circle cx="8" cy="10" r="1.5" fill="currentColor"/></svg>
        <svg width="16" height="12" viewBox="0 0 16 12"><rect x="1" y="8" width="2.5" height="4" rx="0.5" fill="currentColor"/><rect x="5" y="5" width="2.5" height="7" rx="0.5" fill="currentColor"/><rect x="9" y="2" width="2.5" height="10" rx="0.5" fill="currentColor"/><rect x="13" y="0" width="2.5" height="12" rx="0.5" fill="currentColor"/></svg>
        <svg width="24" height="12" viewBox="0 0 24 12"><rect x="0" y="1" width="20" height="10" rx="2" stroke="currentColor" stroke-width="1.2" fill="none"/><rect x="2" y="3" width="14" height="6" rx="1" fill="var(--green)"/><rect x="21" y="4" width="2" height="4" rx="1" fill="currentColor" opacity="0.3"/></svg>
      </span>
    </div>`
  }
  // Legacy (iPhone 8 style)
  return `<div class="status-bar">
    <span class="time">9:41 AM</span>
    <span class="icons">
      <svg width="16" height="12" viewBox="0 0 16 12"><path d="M1 5.5c2-3.5 12-3.5 14 0" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M4 8c1.5-2 6.5-2 8 0" stroke="currentColor" stroke-width="1.5" fill="none"/><circle cx="8" cy="10" r="1.5" fill="currentColor"/></svg>
      <svg width="24" height="12" viewBox="0 0 24 12"><rect x="0" y="1" width="20" height="10" rx="2" stroke="currentColor" stroke-width="1.2" fill="none"/><rect x="2" y="3" width="14" height="6" rx="1" fill="var(--green)"/><rect x="21" y="4" width="2" height="4" rx="1" fill="currentColor" opacity="0.3"/></svg>
    </span>
  </div>`
}

function getScreenStyles(screenId: string, device: DeviceSpec): string {
  const isIPad = device.slug.startsWith('ipad')
  const scale = isIPad ? 1.3 : 1

  switch (screenId) {
    case 'receiver-checkin':
      return `
        .receiver-screen {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 24px;
          background: linear-gradient(180deg, #ffffff 0%, var(--green-50) 100%);
          padding: 0 24px;
        }
        .greeting { font-size: ${20 * scale}px; color: var(--gray-500); font-weight: 500; }
        .checkin-button {
          width: ${200 * scale}px;
          height: ${200 * scale}px;
          border-radius: 50%;
          background: var(--green);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: ${8 * scale}px;
          box-shadow: 0 0 60px rgba(46, 204, 113, 0.35), 0 8px 32px rgba(46, 204, 113, 0.25);
          cursor: pointer;
          position: relative;
        }
        .checkin-button::before {
          content: '';
          position: absolute;
          inset: -12px;
          border-radius: 50%;
          background: rgba(46, 204, 113, 0.12);
        }
        .checkin-icon { font-size: ${40 * scale}px; filter: brightness(0) invert(1); }
        .checkin-text { font-size: ${28 * scale}px; font-weight: 700; color: white; letter-spacing: -0.5px; }
        .checkin-subtitle { font-size: ${15 * scale}px; color: var(--gray-400); text-align: center; }
      `

    case 'receiver-done':
      return `
        .done-screen {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 16px;
          background: linear-gradient(180deg, #ffffff 0%, var(--green-50) 100%);
          padding: 0 32px;
        }
        .done-circle {
          width: ${200 * scale}px;
          height: ${200 * scale}px;
          border-radius: 50%;
          background: rgba(46, 204, 113, 0.12);
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .done-check { font-size: ${80 * scale}px; color: var(--green); }
        .done-title { font-size: ${22 * scale}px; font-weight: 600; color: var(--gray-900); }
        .done-time { font-size: ${15 * scale}px; color: var(--gray-400); }
      `

    case 'mood-selector':
      return `
        .mood-screen {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 20px;
          background: linear-gradient(180deg, #ffffff 0%, var(--green-50) 100%);
          padding: 0 32px;
          position: relative;
        }
        .mood-done-circle {
          width: ${120 * scale}px;
          height: ${120 * scale}px;
          border-radius: 50%;
          background: rgba(46, 204, 113, 0.12);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 8px;
        }
        .mood-check-icon { font-size: ${56 * scale}px; color: var(--green); }
        .mood-sheet {
          position: absolute;
          bottom: 0;
          left: 0;
          right: 0;
          background: rgba(255,255,255,0.97);
          backdrop-filter: blur(20px);
          border-radius: 20px 20px 0 0;
          padding: 28px 24px 40px;
          box-shadow: 0 -8px 40px rgba(0,0,0,0.08);
        }
        .mood-title { font-size: ${20 * scale}px; font-weight: 600; color: var(--gray-900); text-align: center; margin-bottom: 24px; }
        .mood-options { display: flex; justify-content: center; gap: ${24 * scale}px; margin-bottom: 20px; }
        .mood-btn {
          width: ${80 * scale}px;
          height: ${80 * scale}px;
          border-radius: 20px;
          background: var(--gray-50);
          border: 2px solid var(--gray-200);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 4px;
          cursor: pointer;
        }
        .mood-btn.selected { border-color: var(--green); background: var(--green-50); }
        .mood-emoji { font-size: ${32 * scale}px; }
        .mood-label { font-size: ${12 * scale}px; color: var(--gray-500); font-weight: 500; }
        .mood-skip { font-size: 15px; color: var(--gray-400); text-align: center; font-weight: 500; }
      `

    case 'owner-dashboard':
      return `
        .dashboard-scroll {
          flex: 1;
          overflow: hidden;
          padding-bottom: 8px;
        }
        .summary-stats {
          display: flex;
          gap: 8px;
          margin-bottom: 4px;
        }
        .stat-bubble {
          flex: 1;
          text-align: center;
          padding: 12px 8px;
          background: white;
          border-radius: 12px;
        }
        .stat-value { font-size: ${isIPad ? '24' : '20'}px; font-weight: 700; }
        .stat-value.green { color: var(--green); }
        .stat-value.blue { color: var(--blue); }
        .stat-label { font-size: 11px; color: var(--gray-400); margin-top: 2px; }

        .mood-row { display: flex; gap: 12px; align-items: center; padding: 8px 0 0; }
        .mood-item { display: flex; align-items: center; gap: 4px; font-size: 13px; color: var(--gray-600); }

        .timeline-row {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 10px 0;
        }
        .timeline-dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          flex-shrink: 0;
        }
        .timeline-name { font-size: 15px; font-weight: 500; color: var(--gray-800); flex: 1; }
        .timeline-time { font-size: 13px; color: var(--gray-400); }
        .timeline-bar-wrap { width: 60px; height: 4px; background: var(--gray-200); border-radius: 2px; overflow: hidden; }
        .timeline-bar-fill { height: 100%; border-radius: 2px; }

        .receiver-card {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 14px 16px;
          background: white;
          border-radius: 14px;
          margin: 0 16px 10px;
          box-shadow: 0 1px 4px rgba(0,0,0,0.04);
        }
        .avatar {
          width: ${isIPad ? '56' : '50'}px;
          height: ${isIPad ? '56' : '50'}px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: ${isIPad ? '22' : '18'}px;
          font-weight: 700;
          color: white;
          flex-shrink: 0;
        }
        .receiver-info { flex: 1; min-width: 0; }
        .receiver-name { font-size: 16px; font-weight: 600; color: var(--gray-900); }
        .receiver-status { font-size: 13px; display: flex; align-items: center; gap: 4px; margin-top: 2px; }
        .receiver-meta { font-size: 12px; color: var(--gray-400); margin-top: 2px; }
        .streak-col { text-align: center; flex-shrink: 0; }
        .streak-num { font-size: 22px; font-weight: 700; color: var(--green); }
        .streak-label { font-size: 11px; color: var(--gray-400); }

        .check-on-btn {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 8px 14px;
          background: #fff7ed;
          color: var(--orange);
          border: 1.5px solid #fed7aa;
          border-radius: 10px;
          font-size: 13px;
          font-weight: 600;
          margin: 0 16px 10px;
        }
      `

    case 'history-heatmap':
      return `
        .history-scroll { flex: 1; overflow: hidden; }
        .period-picker {
          display: flex;
          gap: 0;
          margin: 0 16px 12px;
          background: var(--gray-100);
          border-radius: 8px;
          padding: 2px;
        }
        .period-btn {
          flex: 1;
          text-align: center;
          padding: 8px;
          font-size: 13px;
          font-weight: 600;
          color: var(--gray-500);
          border-radius: 6px;
          cursor: pointer;
        }
        .period-btn.active {
          background: white;
          color: var(--gray-900);
          box-shadow: 0 1px 3px rgba(0,0,0,0.08);
        }

        .receiver-pills {
          display: flex;
          gap: 8px;
          padding: 0 16px 16px;
          overflow-x: hidden;
        }
        .pill {
          padding: 6px 16px;
          border-radius: 100px;
          font-size: 14px;
          font-weight: 500;
          white-space: nowrap;
          flex-shrink: 0;
        }
        .pill.active { background: var(--green); color: white; }
        .pill.inactive { background: var(--gray-100); color: var(--gray-600); }

        .heatmap-grid {
          display: grid;
          grid-template-columns: repeat(${Math.min(isIPad ? 26 : 15, 15)}, 1fr);
          gap: 3px;
          padding: 0 4px;
        }
        .heatmap-cell {
          aspect-ratio: 1;
          border-radius: 3px;
          min-width: 0;
        }
        .heatmap-label { font-size: 10px; color: var(--gray-400); margin-bottom: 4px; }
        .heatmap-legend {
          display: flex;
          gap: 12px;
          justify-content: center;
          padding: 12px 0 0;
        }
        .legend-item {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 11px;
          color: var(--gray-400);
        }
        .legend-dot {
          width: 10px;
          height: 10px;
          border-radius: 2px;
        }

        .chart-area {
          height: ${isIPad ? '200' : '160'}px;
          position: relative;
          margin: 0 4px;
        }
        .chart-line {
          position: absolute;
          bottom: 0;
          left: 36px;
          right: 0;
          height: 100%;
        }
        .chart-grid-line {
          position: absolute;
          left: 0;
          right: 0;
          border-top: 1px dashed var(--gray-200);
        }
        .chart-y-label {
          position: absolute;
          left: 0;
          font-size: 10px;
          color: var(--gray-400);
          transform: translateY(-50%);
        }
        .chart-stats {
          display: flex;
          gap: 16px;
          padding: 12px 0 0;
        }
        .chart-stat { text-align: center; flex: 1; }
        .chart-stat-value { font-size: 16px; font-weight: 600; color: var(--gray-800); }
        .chart-stat-label { font-size: 11px; color: var(--gray-400); }
      `

    case 'family-management':
      return `
        .family-scroll { flex: 1; overflow: hidden; }
        .family-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin: 0 16px 16px;
        }
        .family-name { font-size: 20px; font-weight: 700; color: var(--gray-900); }
        .tier-badge {
          padding: 4px 12px;
          background: var(--green-light);
          color: var(--green-dark);
          border-radius: 8px;
          font-size: 13px;
          font-weight: 600;
        }
        .member-row {
          display: flex;
          align-items: center;
          gap: 14px;
          padding: 14px 16px;
          margin: 0 16px 8px;
          background: var(--gray-50);
          border-radius: 14px;
        }
        .member-avatar {
          width: 44px;
          height: 44px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-weight: 700;
          color: white;
          font-size: 16px;
          flex-shrink: 0;
        }
        .member-info { flex: 1; }
        .member-name { font-size: 16px; font-weight: 600; color: var(--gray-900); }
        .member-role { font-size: 13px; color: var(--gray-400); }
        .member-status {
          padding: 4px 10px;
          border-radius: 100px;
          font-size: 12px;
          font-weight: 600;
        }
        .status-active { background: var(--green-light); color: var(--green-dark); }
        .status-invited { background: #fff7ed; color: var(--orange); }

        .invite-btn {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          padding: 14px;
          margin: 16px;
          border: 2px dashed var(--gray-300);
          border-radius: 14px;
          color: var(--green);
          font-size: 15px;
          font-weight: 600;
          cursor: pointer;
        }
      `

    case 'plan-selection':
      return `
        .plan-screen {
          flex: 1;
          overflow: hidden;
          padding: 0 16px;
        }
        .plan-heading {
          font-size: 24px;
          font-weight: 700;
          color: var(--gray-900);
          text-align: center;
          margin-bottom: 4px;
        }
        .plan-subheading {
          font-size: 14px;
          color: var(--gray-400);
          text-align: center;
          margin-bottom: 20px;
        }
        .plan-card {
          padding: 20px;
          border-radius: 16px;
          margin-bottom: 12px;
          border: 2px solid var(--gray-200);
          position: relative;
        }
        .plan-card.highlighted {
          border-color: var(--green);
          background: linear-gradient(135deg, var(--green-50), #e8faf0);
        }
        .plan-popular {
          position: absolute;
          top: -10px;
          right: 16px;
          background: var(--green);
          color: white;
          padding: 2px 10px;
          border-radius: 100px;
          font-size: 11px;
          font-weight: 600;
        }
        .plan-name-row { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 4px; }
        .plan-name { font-size: 18px; font-weight: 700; color: var(--gray-900); }
        .plan-price { font-size: 18px; font-weight: 700; color: var(--gray-900); }
        .plan-price span { font-size: 13px; font-weight: 400; color: var(--gray-400); }
        .plan-features-list { padding: 0; list-style: none; }
        .plan-feature {
          display: flex;
          align-items: center;
          gap: 8px;
          font-size: 13px;
          color: var(--gray-600);
          padding: 3px 0;
        }
        .plan-feature .check { color: var(--green); font-weight: 700; font-size: 14px; }
      `

    default:
      return ''
  }
}

function getScreenContent(screenId: string, device: DeviceSpec): string {
  const isIPad = device.slug.startsWith('ipad')

  switch (screenId) {
    case 'receiver-checkin':
      return `
        <div class="receiver-screen">
          <div class="greeting">Good morning!</div>
          <div class="checkin-button">
            <div class="checkin-icon">👋</div>
            <div class="checkin-text">I'm OK</div>
          </div>
          <div class="checkin-subtitle">Tap to let your family know you're OK</div>
        </div>
      `

    case 'receiver-done':
      return `
        <div class="done-screen">
          <div class="done-circle">
            <div class="done-check">✓</div>
          </div>
          <div class="done-title">Your family knows you're OK</div>
          <div class="done-time">Checked in at 9:41 AM</div>
        </div>
      `

    case 'mood-selector':
      return `
        <div class="mood-screen">
          <div class="mood-done-circle">
            <div class="mood-check-icon">✓</div>
          </div>
          <div class="mood-sheet">
            <div class="mood-title">How are you feeling?</div>
            <div class="mood-options">
              <div class="mood-btn selected">
                <div class="mood-emoji">😊</div>
                <div class="mood-label">Good</div>
              </div>
              <div class="mood-btn">
                <div class="mood-emoji">😐</div>
                <div class="mood-label">Okay</div>
              </div>
              <div class="mood-btn">
                <div class="mood-emoji">😴</div>
                <div class="mood-label">Tired</div>
              </div>
            </div>
            <div class="mood-skip">Skip</div>
          </div>
        </div>
      `

    case 'owner-dashboard':
      return `
        <div class="nav-bar"><h1>Dashboard</h1></div>
        <div class="dashboard-scroll">
          <div class="card">
            <div class="card-title">This Week</div>
            <div class="summary-stats">
              <div class="stat-bubble">
                <div class="stat-value green">94%</div>
                <div class="stat-label">Consistency</div>
              </div>
              <div class="stat-bubble">
                <div class="stat-value blue">8:32 AM</div>
                <div class="stat-label">Avg Time</div>
              </div>
              <div class="stat-bubble">
                <div class="stat-value green">13/14</div>
                <div class="stat-label">Check-Ins</div>
              </div>
            </div>
            <div class="mood-row">
              <div class="mood-item">😊 8</div>
              <div class="mood-item">😐 4</div>
              <div class="mood-item">😴 1</div>
            </div>
          </div>

          <div class="card">
            <div class="card-title">Today's Timeline</div>
            ${generateTimelineRows()}
          </div>

          ${generateReceiverCards(isIPad)}
        </div>
        ${generateTabBar('dashboard')}
      `

    case 'history-heatmap':
      return `
        <div class="nav-bar"><h1>History</h1></div>
        <div class="history-scroll">
          <div class="period-picker">
            <div class="period-btn">7 Days</div>
            <div class="period-btn active">30 Days</div>
            <div class="period-btn">90 Days</div>
          </div>
          <div class="receiver-pills">
            <div class="pill active">Mom</div>
            <div class="pill inactive">Dad</div>
          </div>
          <div class="card">
            <div class="card-title">Check-In Heatmap</div>
            <div class="heatmap-grid">
              ${generateHeatmapCells(isIPad)}
            </div>
            <div class="heatmap-legend">
              <div class="legend-item"><div class="legend-dot" style="background:var(--green)"></div>On time</div>
              <div class="legend-item"><div class="legend-dot" style="background:#facc15"></div>Late</div>
              <div class="legend-item"><div class="legend-dot" style="background:var(--red)"></div>Missed</div>
              <div class="legend-item"><div class="legend-dot" style="background:var(--gray-200)"></div>No data</div>
            </div>
          </div>
          <div class="card">
            <div class="card-title">Check-In Trend</div>
            <div class="chart-area">
              ${generateChartSVG(isIPad)}
            </div>
            <div class="chart-stats">
              <div class="chart-stat">
                <div class="chart-stat-value">8:32 AM</div>
                <div class="chart-stat-label">Average</div>
              </div>
              <div class="chart-stat">
                <div class="chart-stat-value">7:15 AM</div>
                <div class="chart-stat-label">Earliest</div>
              </div>
              <div class="chart-stat">
                <div class="chart-stat-value">10:47 AM</div>
                <div class="chart-stat-label">Latest</div>
              </div>
            </div>
          </div>
        </div>
        ${generateTabBar('history')}
      `

    case 'family-management':
      return `
        <div class="nav-bar"><h1>Family</h1></div>
        <div class="family-scroll">
          <div class="family-header">
            <div class="family-name">The Smith Family</div>
            <div class="tier-badge">Family Plan</div>
          </div>

          <div class="member-row">
            <div class="member-avatar" style="background:var(--green)">JS</div>
            <div class="member-info">
              <div class="member-name">Jane Smith</div>
              <div class="member-role">Owner (You)</div>
            </div>
            <div class="member-status status-active">Active</div>
          </div>

          <div class="member-row">
            <div class="member-avatar" style="background:var(--blue)">MS</div>
            <div class="member-info">
              <div class="member-name">Mom</div>
              <div class="member-role">Receiver</div>
            </div>
            <div class="member-status status-active">Active</div>
          </div>

          <div class="member-row">
            <div class="member-avatar" style="background:#8b5cf6">DS</div>
            <div class="member-info">
              <div class="member-name">Dad</div>
              <div class="member-role">Receiver</div>
            </div>
            <div class="member-status status-active">Active</div>
          </div>

          <div class="member-row">
            <div class="member-avatar" style="background:var(--orange)">BS</div>
            <div class="member-info">
              <div class="member-name">Brother</div>
              <div class="member-role">Viewer</div>
            </div>
            <div class="member-status status-invited">Invited</div>
          </div>

          <div class="invite-btn">
            <span style="font-size:20px">+</span>
            Invite Family Member
          </div>
        </div>
        ${generateTabBar('family')}
      `

    case 'plan-selection':
      return `
        <div class="nav-bar" style="padding-top:4px"><h1 style="font-size:20px; text-align:center;">Choose Your Plan</h1></div>
        <div class="plan-screen">
          <div class="plan-subheading">Start with a free trial. Cancel anytime.</div>

          <div class="plan-card">
            <div class="plan-name-row">
              <div class="plan-name">Free</div>
              <div class="plan-price">$0 <span>/month</span></div>
            </div>
            <ul class="plan-features-list">
              <li class="plan-feature"><span class="check">✓</span> 1 Receiver</li>
              <li class="plan-feature"><span class="check">✓</span> Daily check-ins</li>
              <li class="plan-feature"><span class="check">✓</span> Basic escalation</li>
              <li class="plan-feature"><span class="check">✓</span> 7-day history</li>
            </ul>
          </div>

          <div class="plan-card highlighted">
            <div class="plan-popular">Most Popular</div>
            <div class="plan-name-row">
              <div class="plan-name">Family</div>
              <div class="plan-price">$4.99 <span>/month</span></div>
            </div>
            <ul class="plan-features-list">
              <li class="plan-feature"><span class="check">✓</span> 2 Receivers, 2 Viewers</li>
              <li class="plan-feature"><span class="check">✓</span> Custom schedules</li>
              <li class="plan-feature"><span class="check">✓</span> On-demand check-ins</li>
              <li class="plan-feature"><span class="check">✓</span> Mood tracking</li>
              <li class="plan-feature"><span class="check">✓</span> 90-day history</li>
              <li class="plan-feature"><span class="check">✓</span> Pattern alerts</li>
            </ul>
          </div>

          <div class="plan-card">
            <div class="plan-name-row">
              <div class="plan-name">Family+</div>
              <div class="plan-price">$7.99 <span>/month</span></div>
            </div>
            <ul class="plan-features-list">
              <li class="plan-feature"><span class="check">✓</span> 5 Receivers, 5 Viewers</li>
              <li class="plan-feature"><span class="check">✓</span> Critical Alerts (bypass DND)</li>
              <li class="plan-feature"><span class="check">✓</span> PDF reports</li>
              <li class="plan-feature"><span class="check">✓</span> Unlimited history</li>
              <li class="plan-feature"><span class="check">✓</span> Priority support</li>
            </ul>
          </div>
        </div>
      `

    default:
      return '<div style="flex:1;display:flex;align-items:center;justify-content:center;color:var(--gray-400)">Screen not found</div>'
  }
}

function generateTabBar(active: string): string {
  const tabs = [
    { id: 'dashboard', label: 'Dashboard', icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="8" height="8" rx="1"/><rect x="13" y="3" width="8" height="8" rx="1"/><rect x="3" y="13" width="8" height="8" rx="1"/><rect x="13" y="13" width="8" height="8" rx="1"/></svg>` },
    { id: 'history', label: 'History', icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="3" y1="10" x2="21" y2="10"/><line x1="9" y1="4" x2="9" y2="2"/><line x1="15" y1="4" x2="15" y2="2"/></svg>` },
    { id: 'family', label: 'Family', icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="7" r="3"/><circle cx="17" cy="7" r="2.5"/><path d="M3 21v-2a4 4 0 014-4h4a4 4 0 014 4v2"/><path d="M17 14a3 3 0 013 3v4"/></svg>` },
    { id: 'settings', label: 'Settings', icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 01-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/></svg>` },
  ]

  return `<div class="tab-bar">${tabs.map(t =>
    `<div class="tab-item ${t.id === active ? 'active' : ''}">${t.icon}<span>${t.label}</span></div>`
  ).join('')}</div>`
}

function generateTimelineRows(): string {
  const data = [
    { name: 'Mom', color: 'var(--green)', time: '8:15 AM', pct: 65 },
    { name: 'Dad', color: 'var(--green)', time: '9:02 AM', pct: 72 },
  ]
  return data.map(d => `
    <div class="timeline-row">
      <div class="timeline-dot" style="background:${d.color}"></div>
      <div class="timeline-name">${d.name}</div>
      <div class="timeline-time">${d.time}</div>
      <div class="timeline-bar-wrap">
        <div class="timeline-bar-fill" style="width:${d.pct}%;background:${d.color}"></div>
      </div>
    </div>
  `).join('')
}

function generateReceiverCards(isIPad: boolean): string {
  const receivers = [
    { initials: 'MS', name: 'Mom', bg: 'var(--blue)', status: 'Checked in', statusColor: 'var(--green)', time: '8:15 AM', streak: 12, mood: '😊' },
    { initials: 'DS', name: 'Dad', bg: '#8b5cf6', status: 'Checked in', statusColor: 'var(--green)', time: '9:02 AM', streak: 8, mood: '😐' },
  ]
  return receivers.map(r => `
    <div class="receiver-card">
      <div class="avatar" style="background:${r.bg}">${r.initials}</div>
      <div class="receiver-info">
        <div class="receiver-name">${r.name}</div>
        <div class="receiver-status" style="color:${r.statusColor}">● ${r.status}</div>
        <div class="receiver-meta">🕐 ${r.time} ${r.mood ? `  ${r.mood}` : ''}</div>
      </div>
      <div class="streak-col">
        <div class="streak-num">${r.streak}</div>
        <div class="streak-label">day streak</div>
      </div>
    </div>
  `).join('')
}

function generateHeatmapCells(isIPad: boolean): string {
  const cols = isIPad ? 26 : 15
  const rows = 7
  const colors = ['var(--green)', '#facc15', 'var(--red)', 'var(--gray-200)', 'var(--gray-100)']
  // Weighted toward green for a nice-looking heatmap
  const weights = [60, 10, 5, 10, 15]
  let cells = ''
  for (let i = 0; i < rows * cols; i++) {
    let r = Math.random() * 100
    let color = colors[4]
    let cumulative = 0
    for (let j = 0; j < weights.length; j++) {
      cumulative += weights[j]
      if (r < cumulative) {
        color = colors[j]
        break
      }
    }
    cells += `<div class="heatmap-cell" style="background:${color}"></div>`
  }
  return cells
}

function generateChartSVG(isIPad: boolean): string {
  const w = isIPad ? 960 : 360
  const h = isIPad ? 200 : 160
  // Generate a trend line that looks like morning check-in times
  const points = 14
  const pts: string[] = []
  const dots: string[] = []
  for (let i = 0; i < points; i++) {
    const x = 36 + (i / (points - 1)) * (w - 50)
    // Simulate ~8:30 AM range with some variance (normalized to chart height)
    const y = h - (30 + Math.random() * 60 + Math.sin(i * 0.5) * 20)
    pts.push(`${x},${y}`)
    dots.push(`<circle cx="${x}" cy="${y}" r="3.5" fill="var(--green)"/>`)
  }
  return `
    <svg width="100%" height="100%" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
      <!-- Grid lines -->
      <line x1="36" y1="${h * 0.2}" x2="${w}" y2="${h * 0.2}" stroke="var(--gray-200)" stroke-width="0.5" stroke-dasharray="4"/>
      <line x1="36" y1="${h * 0.5}" x2="${w}" y2="${h * 0.5}" stroke="var(--gray-200)" stroke-width="0.5" stroke-dasharray="4"/>
      <line x1="36" y1="${h * 0.8}" x2="${w}" y2="${h * 0.8}" stroke="var(--gray-200)" stroke-width="0.5" stroke-dasharray="4"/>
      <!-- Y labels -->
      <text x="0" y="${h * 0.2 + 4}" fill="var(--gray-400)" font-size="10" font-family="Inter,sans-serif">12 PM</text>
      <text x="2" y="${h * 0.5 + 4}" fill="var(--gray-400)" font-size="10" font-family="Inter,sans-serif">9 AM</text>
      <text x="2" y="${h * 0.8 + 4}" fill="var(--gray-400)" font-size="10" font-family="Inter,sans-serif">6 AM</text>
      <!-- Trend line -->
      <polyline points="${pts.join(' ')}" fill="none" stroke="var(--green)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
      ${dots.join('')}
    </svg>
  `
}
