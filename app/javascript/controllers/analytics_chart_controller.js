// app/javascript/controllers/analytics_chart_controller.js
//
// ==============================================================================
// AnalyticsChartController（H-4: グラフ・進捗分析ページの描画コントローラー）
// ==============================================================================
//
// 【重要: UMDビルドでは Chart.register() の手動呼び出しが不要な場合がある】
//   dist/chart.umd.js は <script> タグでの単純な読み込みを想定したビルドで、
//   Chart.js公式サイトの「Getting Started」のCDN利用例でも
//   Chart.register() の呼び出しは行われていない（読み込み時点で
//   折れ線・棒グラフ等の全コンポーネントが自動登録済みのため）。
//
//   このビルドでは Chart.registerables が配列として存在しない、または
//   undefined になることがあり、従来通り
//   Chart.register(...Chart.registerables) を無条件に呼ぶと
//   「Chart.registerables is not iterable」で例外が発生し、
//   このファイルを静的 import している controllers/index.js 全体が
//   読み込み停止し、サイト上の全Stimulusコントローラーが
//   機能しなくなる（過去に発生した障害と同じ連鎖停止パターン）。
//
//   Array.isArray() で「配列として確実に存在する場合のみ」登録を行うことで、
//   自動登録版（registerablesが存在しない）でもエラーにならず、
//   手動登録が必要な版（registerablesが配列で存在する）でも
//   正しく登録される、両方のビルドパターンに対応できる安全な実装にする。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"
import "chart.js"

// UMDビルドが window.Chart にコンストラクタを設定する。
// このタイミングで取得すれば、import の完了後のため確実に値が入っている。
const Chart = window.Chart

// Array.isArray を使うことで「プロパティが存在しない（undefined）」
// 「配列でない別の値」の両方を安全に弾き、登録済みビルドでは
// 何もせずスキップする（エラーを起こさない）。
if (Array.isArray(Chart.registerables)) {
  Chart.register(...Chart.registerables)
}

export default class extends Controller {
  // target: HTML側で data-analytics-chart-target="habitCanvas" のように
  //         指定された要素を this.habitCanvasTarget として参照できるようにする。
  static targets = ["habitCanvas", "moodCanvas"]

  // values: HTML側で data-analytics-chart-habit-chart-value="..." のように
  //         指定された JSON 文字列を自動でパースしてオブジェクトとして受け取る。
  static values = {
    habitChart: Object,
    moodChart: Object
  }

  // connect(): この要素がDOMに接続されたタイミングで実行される
  //            （Turbo によるページ遷移時にも毎回呼ばれる）。
  connect() {
    this._renderHabitChart()
    this._renderMoodChart()
  }

  // disconnect(): この要素がDOMから削除されるタイミングで実行される
  //               （Turbo Drive によるページ遷移時など）。
  //
  // 【なぜ Chart インスタンスを destroy() する必要があるのか】
  //   Chart.js のインスタンスは内部で canvas のイベントリスナーや
  //   アニメーションタイマーを保持している。
  //   destroy() せずに次のページへ遷移すると、これらが解放されずに残り続け
  //   メモリリークの原因になる（このプロジェクトの他のコントローラーでも
  //   一貫して採用されている設計方針）。
  disconnect() {
    if (this._habitChartInstance) {
      this._habitChartInstance.destroy()
      this._habitChartInstance = null
    }
    if (this._moodChartInstance) {
      this._moodChartInstance.destroy()
      this._moodChartInstance = null
    }
  }

  // _renderHabitChart(): 習慣別達成率の折れ線グラフを描画する
  _renderHabitChart() {
    if (!this.hasHabitCanvasTarget) return

    const chartData = this.habitChartValue
    if (!chartData || !chartData.labels || chartData.labels.length === 0) return

    const datasets = chartData.datasets.map((dataset) => ({
      label:           dataset.label,
      data:            dataset.data,
      borderColor:     dataset.color,
      backgroundColor: dataset.color,
      tension:         0.3,
      pointRadius:     3,
      pointHoverRadius: 5
    }))

    this._habitChartInstance = new Chart(this.habitCanvasTarget, {
      type: "line",
      data: {
        labels:   chartData.labels,
        datasets: datasets
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            min: 0,
            max: 100,
            ticks: {
              callback: (value) => `${value}%`
            }
          }
        },
        plugins: {
          legend: {
            position: "bottom",
            labels: {
              boxWidth: 12,
              font: { size: 11 }
            }
          }
        }
      }
    })
  }

  // _renderMoodChart(): 気分スコアの棒グラフを描画する
  _renderMoodChart() {
    if (!this.hasMoodCanvasTarget) return

    const chartData = this.moodChartValue
    if (!chartData || !chartData.labels || chartData.labels.length === 0) return

    this._moodChartInstance = new Chart(this.moodCanvasTarget, {
      type: "bar",
      data: {
        labels: chartData.labels,
        datasets: [
          {
            label: "気分スコア",
            data:  chartData.data,
            backgroundColor: "#f59e0b",
            borderRadius: 4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            min: 0,
            max: 5,
            ticks: {
              stepSize: 1
            }
          }
        },
        plugins: {
          legend: { display: false }
        }
      }
    })
  }
}