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
//   「Chart.registerables is not iterable」で例外が発生する。
//
//   Array.isArray() で「配列として確実に存在する場合のみ」登録を行うことで、
//   自動登録版（registerablesが存在しない）でもエラーにならず、
//   手動登録が必要な版（registerablesが配列で存在する）でも
//   正しく登録される、両方のビルドパターンに対応できる安全な実装にする。
//
// ==============================================================================
// Lighthouse 対応: chart.js を「グラフのページを開いたときだけ」読み込む
// ==============================================================================
//
// 【以前の問題】
//   このファイルの一番上で import "chart.js" していたため、
//   controllers/index.js（アプリ起動時に全コントローラーを読み込む）経由で、
//   ログイン画面やダッシュボードでも chart.js（約 60KB）が毎回読み込まれていた。
//   Lighthouse の「使用していない JavaScript の削減」で指摘されていた。
//   また、chart.js の読み込みで例外が起きると index.js 全体が止まり、
//   サイト上の全 Stimulus コントローラーが動かなくなる危険もあった。
//
// 【変更内容】
//   import("chart.js")（動的 import）を connect() の中で呼び、
//   グラフの要素（data-controller="analytics-chart"）が画面に出たときだけ読み込む。
//   config/importmap.rb でも preload: false にして、全ページでの先読みをやめている。
//
// 【動的 import とは】
//   import("...") は関数のように呼べる import で、呼んだ時点でファイルを取りに行き、
//   読み込みが終わると Promise（あとで結果が届く約束）が完了する。
//   読み込みに失敗しても、例外はこのコントローラーの中だけで扱えるため、
//   ほかのコントローラーには影響しない。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

// -----------------------------------------------------------------------------
// chart.js の読み込み（1回だけ行い、2回目以降は使い回す）
// -----------------------------------------------------------------------------
//
// 【chartPromise をコントローラーの外に置く理由】
//   コントローラーは画面を開くたびに作り直されるが、このファイル（モジュール）の
//   変数はページを読み込み直すまで残る。ここに Promise を保存しておけば、
//   2回目以降にグラフのページを開いたときは、ファイルを取りに行かずにすぐ使える。
let chartPromise = null

const loadChart = () => {
  if (!chartPromise) {
    chartPromise = import("chart.js")
      .then(() => {
        // UMDビルドが window.Chart にコンストラクタを設定する。
        // import の完了後なので、ここでは確実に値が入っている。
        const Chart = window.Chart

        // Array.isArray を使うことで「プロパティが存在しない（undefined）」
        // 「配列でない別の値」の両方を安全に弾き、登録済みビルドでは
        // 何もせずスキップする（エラーを起こさない）。
        if (Array.isArray(Chart.registerables)) {
          Chart.register(...Chart.registerables)
        }
        return Chart
      })
      .catch((error) => {
        // 読み込みに失敗した場合（Render のスリープ復帰中の通信失敗など）は、
        // 保存した Promise を捨てて、次にページを開いたときに取り直せるようにする。
        // （失敗した Promise を残すと、ページを読み込み直すまでずっと失敗し続ける）
        chartPromise = null
        throw error
      })
  }
  return chartPromise
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
  //
  // 【async にした理由】
  //   chart.js の読み込み（await loadChart()）が終わるまで待ってから描画するため。
  //
  // 【connectId（接続の番号）を使う理由】
  //   読み込みを待っている間に、利用者が別のページへ移動したり、
  //   Turbo のキャッシュから同じページが表示し直されたりすることがある。
  //   そのまま描画すると、消えた画面に描こうとしたり、同じ canvas に2回描いて
  //   「Canvas is already in use」というエラーになったりする。
  //   connect / disconnect のたびに番号を進め、待っている間に番号が変わっていたら
  //   （＝もう別の接続になっていたら）描画せずに終わる。
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

    // 待っている間に別の接続になった、または画面から外れた場合は描画しない
    if (connectId !== this._connectId || !this.element.isConnected) return

    this._renderHabitChart(Chart)
    this._renderMoodChart(Chart)
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
    // 接続の番号を進め、読み込み待ちの connect() が描画しないようにする
    this._connectId = (this._connectId || 0) + 1

    if (this._habitChartInstance) {
      this._habitChartInstance.destroy()
      this._habitChartInstance = null
    }
    if (this._moodChartInstance) {
      this._moodChartInstance.destroy()
      this._moodChartInstance = null
    }
  }

  // _renderHabitChart(Chart): 習慣別達成率の折れ線グラフを描画する
  //   引数 Chart: 読み込みが終わった Chart.js のコンストラクタ
  _renderHabitChart(Chart) {
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

  // _renderMoodChart(Chart): 気分スコアの棒グラフを描画する
  //   引数 Chart: 読み込みが終わった Chart.js のコンストラクタ
  _renderMoodChart(Chart) {
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