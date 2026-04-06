// app/javascript/controllers/voice_input_controller.js
// =============================================================
// Stimulus コントローラー: 音声入力（B-7 新規作成）
// =============================================================
//
// 【役割】
//   Web Speech API（SpeechRecognition）を使って音声入力を実現する。
//   🎤 ボタンをクリックすると音声認識を開始/停止する。
//   認識した文字列をテキストエリアに追記する。
//
// 【Web Speech API について】
//   ブラウザに標準搭載された音声認識 API。
//   Chrome (デスクトップ・Android) / Safari (iOS 14.5+) で動作する。
//   Firefox など未対応ブラウザでは graceful degradation（優雅な劣化）として
//   🎤 ボタンを非表示にする。
//   外部APIへの送信は行わない（ブラウザ内処理のみ）。
//
// 【webkitSpeechRecognition について】
//   Chrome は標準の SpeechRecognition の前に
//   webkitSpeechRecognition という独自実装を提供している。
//   両方に対応するために「SpeechRecognition || webkitSpeechRecognition」
//   という記述でどちらかが使えれば利用する。
//
// 【connect() でのブラウザ対応チェックについて】
//   コントローラーが DOM に接続されたとき（= ページ読み込み時）に
//   ブラウザの対応状況を確認する。
//   未対応なら 🎤 ボタンを非表示にすることで
//   「タップしても何も起きない」という混乱を防ぐ。
//
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ===========================================================
  // Targets の定義
  // ===========================================================
  static targets = [
    // field: 音声認識結果のテキストを書き込む入力要素（テキストエリアなど）
    //        data-voice-input-target="field" を付けた要素がターゲットになる
    "field",
    // button: 🎤 ボタン
    //         録音中は赤くして「録音中」をユーザーに示す
    "button"
  ]

  // ===========================================================
  // connect() ライフサイクルフック
  // ===========================================================
  //
  // Stimulus コントローラーが DOM に接続されたときに自動的に呼ばれる。
  // ブラウザの対応確認と SpeechRecognition の初期設定をここで行う。
  connect() {
    // SpeechRecognition または webkitSpeechRecognition が使えるか確認する
    // window.SpeechRecognition: 標準準拠ブラウザ（Firefox の将来バージョンなど）
    // window.webkitSpeechRecognition: Chrome / Safari
    const SpeechRecognition =
      window.SpeechRecognition || window.webkitSpeechRecognition

    // 未対応ブラウザ（Firefox など）の場合
    if (!SpeechRecognition) {
      // 🎤 ボタンを非表示にする
      // 「タップしても何も起きない」という混乱を防ぐための graceful degradation
      if (this.hasButtonTarget) {
        this.buttonTarget.style.display = "none"
      }
      // 後続の処理は不要なので早期リターンする
      return
    }

    // SpeechRecognition のインスタンスを生成する
    // インスタンス変数（this.recognition）に保存して
    // toggle() メソッドからアクセスできるようにする
    this.recognition = new SpeechRecognition()

    // lang: 認識する言語を日本語に設定する
    // "ja-JP" = 日本語（日本）
    // この設定がないと英語で認識しようとする場合がある
    this.recognition.lang = "ja-JP"

    // continuous: false にすると「発話が終わったら自動停止」する
    // true にすると手動でstopを呼ぶまで認識し続ける
    // メモ入力は短い文章を想定しているため false を使う
    this.recognition.continuous = false

    // interimResults: true にすると「認識途中の結果」も返す
    // false にすると「確定した結果」のみ返す
    // メモ入力では確定結果のみで十分なため false を使う
    this.recognition.interimResults = false

    // 録音状態を管理するフラグ
    // toggle() メソッドで開始/停止を切り替えるために使う
    this._isListening = false

    // onresult: 音声認識が成功したときのコールバック
    // event.results に認識結果の配列が入っている
    this.recognition.onresult = (event) => {
      // event.results[0][0].transcript: 最初の認識結果のテキスト
      // transcript は認識したテキスト文字列
      const transcript = event.results[0][0].transcript

      // テキストエリアに認識結果を追記する
      // 「+=」で追記することで、既存のメモを消さずに後ろに付け加える
      // 追記前に半角スペースを1つ入れることで、前の文章とくっつかないようにする
      if (this.hasFieldTarget) {
        const current = this.fieldTarget.value
        // 既存テキストが空でなければスペースを挟む
        this.fieldTarget.value = current
          ? current + " " + transcript
          : transcript

        // input イベントを手動で発火して文字数カウンターを更新する
        // テキストエリアへの JS による直接代入では input イベントが発火しないため
        // 手動でイベントを作成して発火させる必要がある
        this.fieldTarget.dispatchEvent(new Event("input", { bubbles: true }))
      }

      // 認識が終わったらボタンを元の状態に戻す
      this._setListeningState(false)
    }

    // onerror: 音声認識中にエラーが発生したときのコールバック
    this.recognition.onerror = (event) => {
      console.error("音声認識エラー:", event.error)

      // "not-allowed": マイクへのアクセスが拒否された
      // この場合のみユーザーにメッセージを表示する
      // その他のエラー（network, no-speech など）は静かに終了する
      if (event.error === "not-allowed") {
        alert("マイクへのアクセスを許可してください。\nブラウザの設定 → このサイトの権限 → マイク → 許可")
      }

      this._setListeningState(false)
    }

    // onend: 音声認識が終了したときのコールバック
    // エラーや自動停止の場合も呼ばれる
    this.recognition.onend = () => {
      this._setListeningState(false)
    }
  }

  // ===========================================================
  // disconnect() ライフサイクルフック
  // ===========================================================
  //
  // Stimulus コントローラーが DOM から切り離されたとき（= ページ遷移時など）
  // に自動的に呼ばれる。
  // 認識中のまま画面遷移するとマイクが解放されないため、ここで停止する。
  disconnect() {
    if (this.recognition && this._isListening) {
      this.recognition.stop()
    }
  }

  // ===========================================================
  // toggle メソッド
  // ===========================================================
  //
  // 【役割】
  //   🎤 ボタンをクリックしたとき、音声認識の開始/停止を切り替える。
  //
  // 【_isListening フラグについて】
  //   _isListening が true = 現在録音中 → stop() を呼んで停止する
  //   _isListening が false = 現在停止中 → start() を呼んで開始する
  toggle() {
    // recognition が初期化されていない（= 未対応ブラウザ）場合は何もしない
    if (!this.recognition) return

    if (this._isListening) {
      // 録音中 → 停止する
      this.recognition.stop()
      this._setListeningState(false)
    } else {
      // 停止中 → 開始する
      try {
        this.recognition.start()
        this._setListeningState(true)
      } catch (error) {
        // start() は既に開始済みの場合にエラーを投げることがある
        // その場合は無視して停止状態にリセットする
        console.error("音声認識の開始に失敗しました:", error)
        this._setListeningState(false)
      }
    }
  }

  // ===========================================================
  // Private メソッド
  // ===========================================================

  // _setListeningState
  // 【役割】
  //   録音状態のフラグを更新し、🎤 ボタンの見た目を変える。
  //
  // 【isListening が true の場合（録音中）】
  //   ボタンに録音中スタイルを適用する
  //   aria-label を「音声入力を停止する」に変更する
  //
  // 【isListening が false の場合（停止中）】
  //   ボタンを通常スタイルに戻す
  //   aria-label を「音声入力を開始する」に戻す
  _setListeningState(isListening) {
    this._isListening = isListening

    if (!this.hasButtonTarget) return

    if (isListening) {
      // 録音中: ボタンを赤くしてアニメーションを付ける
      // animate-pulse は Tailwind CSS のクラスで「点滅するアニメーション」を適用する
      this.buttonTarget.classList.add(
        "text-red-500", "bg-red-50", "border-red-300", "animate-pulse"
      )
      this.buttonTarget.classList.remove("text-gray-500")
      this.buttonTarget.setAttribute("aria-label", "音声入力を停止する")
    } else {
      // 停止中: ボタンを元のスタイルに戻す
      this.buttonTarget.classList.remove(
        "text-red-500", "bg-red-50", "border-red-300", "animate-pulse"
      )
      this.buttonTarget.classList.add("text-gray-500")
      this.buttonTarget.setAttribute("aria-label", "音声入力を開始する")
    }
  }
}