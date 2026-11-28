// app/javascript/controllers/admin_usage_chart_controller.js
//
// ==============================================================================
// AdminUsageChartController: 管理画面（/admin）の「週ごとの推移」のグラフを描く
// ==============================================================================
//
// 【グラフ・進捗分析ページ（analytics_chart_controller.js）と同じ読み込み方にする】
//   chart.js（約 60KB）はファイルの一番上で import せず、
//   connect() の中で import("chart.js")（動的 import）を呼び、
//   この要素（data-controller="admin-usage-chart"）が画面に出たときだけ読み込む。
//   config/importmap.rb で chart.js は preload: false にしてあるので、ほかのページでは読み込まれない。
//
// 【UMD 版の chart.js について】
//   vendor/javascript/chart.js.js は UMD 版で、読み込むと window.Chart が作られる。
//   Chart.registerables が配列のときだけ登録する（ない版でもエラーにしない）。
//
// 【このファイルで ! を使っていない理由】
//   ターミナルに cat の heredoc で貼り付けると、bash が ! を
//   「過去のコマンドを呼び出す記号」として扱い、貼り付けが壊れることがあるため。
//   否定は === false や === null で書いている。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

// chart.js の読み込み（ページを読み込み直すまで、2回目以降は使い回す）
let chartPromise = null

const loadChart = () => {
  if (chartPromise === null) {
    chartPromise = import("chart.js")
      .then(() => {
        const Chart = window.Chart
        if (Array.isArray(Chart.registerables)) {
          Chart.register(...Chart.registerables)
        }
        return Chart
      })
      .catch((error) => {
        // 読み込みに失敗したら、次にページを開いたときに取り直せるよう Promise を捨てる
        chartPromise = null
        throw error
      })
  }
  return chartPromise
}

export default class extends Controller {
  // HTML の data-admin-usage-chart-target="signupsCanvas" などで指定した canvas
  static targets = ["signupsCanvas", "recordingCanvas"]

  // HTML の data-admin-usage-chart-signups-value="..." などで渡した JSON（{ labels: [...], data: [...] }）
  static values = {
    signups: Object,
    recording: Object
  }

  // connect(): この要素が画面に出たときに実行される（Turbo の画面遷移でも毎回呼ばれる）
  //
  // 【connectId（接続の番号）を使う理由】
  //   chart.js の読み込みを待っている間に別のページへ移動した場合などに、
  //   消えた画面や、すでに描いた canvas にもう一度描こうとしないようにするため。
  async connect() {
    this._connectId = (this._connectId || 0) + 1
    const connectId = this._connectId

    let Chart
    try {
      Chart = await loadChart()
    } catch (error) {
      console.error("グラフの部品（Chart.js）を読み込めませんでした。ページを再読み込みしてください。", error)
      return
    }

    if (connectId !== this._connectId || this.element.isConnected === false) return

    this._charts = [
      this._renderChart(Chart, this.hasSignupsCanvasTarget ? this.signupsCanvasTarget : null, this.signupsValue, "bar", "#2563eb"),
      this._renderChart(Chart, this.hasRecordingCanvasTarget ? this.recordingCanvasTarget : null, this.recordingValue, "line", "#16a34a")
    ].filter((chart) => chart !== null)
  }

  // disconnect(): この要素が画面から消えるときに実行される
  //   Chart.js のインスタンスは canvas のイベントやタイマーを持っているため、
  //   destroy() で片付けないとメモリが解放されない。
  disconnect() {
    this._connectId = (this._connectId || 0) + 1
    ;(this._charts || []).forEach((chart) => chart.destroy())
    this._charts = []
  }

  // _renderChart: 1つのグラフを描き、Chart.js のインスタンスを返す（描けないときは null）
  //   type : "bar"（棒グラフ）または "line"（折れ線グラフ）
  //   color: グラフの色
  _renderChart(Chart, canvas, chartData, type, color) {
    if (canvas === null) return null
    if (chartData === null || Array.isArray(chartData.labels) === false) return null

    return new Chart(canvas, {
      type: type,
      data: {
        labels: chartData.labels,
        datasets: [
          {
            data: chartData.data,
            borderColor: color,
            backgroundColor: color,
            tension: 0.3,
            borderRadius: 4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          // 人数なので、目盛りは 0 から始めて整数だけにする
          y: { beginAtZero: true, ticks: { precision: 0 } }
        },
        plugins: {
          legend: { display: false }
        }
      }
    })
  }
}
