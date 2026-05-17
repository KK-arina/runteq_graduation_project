// app/javascript/controllers/ai_analysis_polling_controller.js
//
// ============================================================
// AI分析ポーリングコントローラ（E-5 新規追加）
// ============================================================
//
// 【このファイルの役割】
//   AI分析が「待機中」の状態のとき、一定間隔でページの AI分析
//   セクションだけを再取得し、完了したら自動で表示を切り替える。
//
// 【なぜ Turbo.visit（ページ全体更新）を使わないのか】
//   Turbo.visit はページ全体を再読み込みするため、スクロール位置が
//   先頭に戻ってしまいユーザー体験が悪い。
//   代わりに fetch + Turbo Streams / innerHTML 部分更新を使うことで
//   スクロール位置を維持したまま「AI分析セクションだけ」を更新できる。
//
// 【Stimulus の Value API を使う理由】
//   data-* 属性からコントローラに値を渡す Stimulus の仕組み。
//   HTML テンプレートに URL や間隔をハードコードせず、
//   ビューから動的に渡せるため、ルート変更に強い。
//
// 【ポーリングが止まる条件】
//   analysis_comment を含む要素が DOM から消えた（= 完了UI に切り替わった）
//   ことを検知して clearInterval する。
//   これにより「完了後もポーリングし続けてサーバーに無駄な負荷をかける」
//   問題を防ぐ。
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ----------------------------------------------------------------
  // static values
  //   Stimulus の Value API の宣言。
  //   ここで宣言した名前は data-[identifier]-[name]-value 属性から
  //   自動的に読み込まれ、this.[name]Value でアクセスできる。
  //
  //   url      → ポーリング先の URL（週次振り返り詳細ページのパス）
  //   interval → ポーリング間隔（ミリ秒）。デフォルト 10000ms = 10秒
  // ----------------------------------------------------------------
  static values = {
    url:      String,
    interval: { type: Number, default: 10000 }
  }

  // ----------------------------------------------------------------
  // connect()
  //   Stimulus のライフサイクルメソッド。
  //   この要素が DOM に接続されたとき自動で呼ばれる。
  //   ポーリングの開始はここで行う。
  // ----------------------------------------------------------------
  connect() {
    // setInterval でポーリングを開始し、タイマーIDを保持する。
    // disconnect() や完了検知で clearInterval するために必要。
    this.timer = setInterval(() => {
      this.#poll()
    }, this.intervalValue)
  }

  // ----------------------------------------------------------------
  // disconnect()
  //   この要素が DOM から切り離されたとき自動で呼ばれる。
  //   ページ遷移時などにポーリングが残り続けてメモリリークする問題を防ぐ。
  // ----------------------------------------------------------------
  disconnect() {
    this.#stopPolling()
  }

  // ----------------------------------------------------------------
  // #poll()（プライベートメソッド）
  //   サーバーに対して現在のページ URL を fetch し、
  //   レスポンスの HTML から AI分析セクションを抽出して
  //   現在の DOM と差し替える。
  //
  //   # で始まるメソッドは JavaScript のプライベートメソッド（ES2022）。
  //   クラス外部から呼ばれることを防ぐ意図を明示できる。
  // ----------------------------------------------------------------
  async #poll() {
    try {
      // fetch で同じページを再取得する。
      // credentials: "same-origin" はクッキー（セッション情報）を
      // リクエストに含める指定。これがないとログインが必要なページで
      // 401 エラーが返ってくる。
      const response = await fetch(this.urlValue, {
        credentials: "same-origin",
        headers: {
          // Rails に「通常のページリクエスト」と認識させるために必要。
          // これがないと JSON レスポンスが返ってくる場合がある。
          Accept: "text/html"
        }
      })

      // fetch が失敗した場合（ネットワークエラー等）は静かにスキップ。
      // エラーをユーザーに見せず、次のポーリングで自動リトライする。
      if (!response.ok) return

      // レスポンスの HTML テキストを取得する。
      const html = await response.text()

      // DOMParser でレスポンス HTML を解析し、DOM ツリーとして扱える状態にする。
      // document.createElement("div") に innerHTML を入れる方法もあるが、
      // DOMParser の方がブラウザ標準の安全なパース方法。
      const parser  = new DOMParser()
      const newDoc  = parser.parseFromString(html, "text/html")

      // 新しい HTML から AI分析セクション全体を取得する。
      // id="ai-analysis-section" で一意に特定する。
      const newSection = newDoc.getElementById("ai-analysis-section")

      if (!newSection) {
        // 新しい HTML にセクションがない = 分析レコード自体が消えた（異常系）
        // ポーリングを停止して終了する。
        this.#stopPolling()
        return
      }

      // 新しいセクションに「待機中UI」がなくなっていれば分析完了を意味する。
      // data-controller="ai-analysis-polling" 属性を持つ要素がなければ完了。
      const stillWaiting = newSection.querySelector("[data-controller='ai-analysis-polling']")

      // 現在の DOM の AI分析セクションを新しい HTML で置き換える。
      // outerHTML の置き換えにより、Stimulus は新しい DOM を自動検出して
      // 必要なコントローラを接続し直す（旧コントローラは disconnect する）。
      const currentSection = document.getElementById("ai-analysis-section")
      if (currentSection) {
        currentSection.outerHTML = newSection.outerHTML
      }

      // 完了していればポーリングを停止する。
      // outerHTML 置き換え後はこの要素自体が DOM から消えているため
      // disconnect() が自動で呼ばれるが、明示的に止めることでより安全になる。
      if (!stillWaiting) {
        this.#stopPolling()
      }

    } catch (error) {
      // fetch 自体が例外を投げた場合（ネットワーク断等）はコンソールに記録して継続。
      // ユーザーには何も表示せず、次のポーリングで自動リトライする設計。
      console.warn("[AiAnalysisPollingController] ポーリング中にエラーが発生しました:", error)
    }
  }

  // ----------------------------------------------------------------
  // #stopPolling()（プライベートメソッド）
  //   タイマーをクリアしてポーリングを停止する。
  //   connect() / disconnect() / 完了検知の3箇所から呼ばれるため
  //   メソッドとして切り出して DRY にする。
  // ----------------------------------------------------------------
  #stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }
}