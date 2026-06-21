// app/javascript/controllers/voice_input_controller.js
//
// ==============================================================================
// VoiceInputController（H-3: 音声入力機能）最終確定版 v2
// ==============================================================================
//
// 【このコントローラーの役割】
//   Web Speech API（SpeechRecognition）を使い、
//   テキストエリア・入力フィールドに音声でテキストをリアルタイム追記する。
//   音声データはブラウザ内で処理される。
//   ※ Chrome 使用時は Google のサーバーで音声処理が行われる場合がある。
//
// 【対応ブラウザ】
//   Chrome（デスクトップ・Android）: window.webkitSpeechRecognition
//   Safari（iOS 14.5+ / macOS）   : window.SpeechRecognition
//   Firefox                       : デフォルトで無効化されているため未対応扱い
//                                    → connect() で🎤ボタンを自動非表示にする
//
// 【リアルタイム追記の実装方針（最重要）】
//   handleResult() 内で event.results を 0 から全件ループし、
//   isFinal=true（確定結果）と isFinal=false（暫定結果＝話している途中）を
//   それぞれ別の変数に集計する。
//   フィールドへ書き込む際は startValue + finalTranscript + interimTranscript
//   をすべて連結する。これにより話している最中から文字が画面に出てくる。
//
// 【複数フィールド同時録音の防止】
//   window.activeVoiceController にアクティブなコントローラーを記録し、
//   新しいフィールドで録音開始すると前のコントローラーの録音を先に停止する。
//
// 【連打防止】
//   isProcessing フラグで start() 呼び出し中〜onstart発火までをロックする。
//
// 【インライントースト v2】
//   #flash-area は使わず、🎤ボタンの直後にインラインで警告メッセージを挿入する。
//   表示位置の基準(position:relative)はHTML側のclass属性で用意する設計とし、
//   JS側ではstyle.positionを強制付与しない（レイアウト責務の分離）。
//   ✕ボタンのクリックハンドラーはonclickへの代入とし、
//   再利用時にaddEventListenerが重複登録されることを防ぐ。
//
// 【HTML 側の使い方】
//   <div class="relative" data-controller="voice-input">
//     <textarea data-voice-input-target="field"></textarea>
//     <button data-voice-input-target="button"
//             data-action="click->voice-input#toggle">🎤</button>
//   </div>
//   ※ 親divに class="relative" が必須（showToastの絶対配置の基準になる）
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "button"]

  // ============================================================
  // connect(): コントローラーが DOM に接続されたとき自動で呼ばれる
  // ============================================================
  connect() {
    const SpeechRecognitionAPI =
      window.SpeechRecognition || window.webkitSpeechRecognition

    if (!SpeechRecognitionAPI) {
      // 未対応ブラウザ: 🎤ボタンを非表示にする
      if (this.hasButtonTarget) {
        this.buttonTarget.style.display = "none"
      }
      return
    }

    this.recognition = new SpeechRecognitionAPI()
    this.recognition.lang = "ja-JP"
    this.recognition.continuous = true
    this.recognition.interimResults = true

    this.recognition.onresult = this.handleResult.bind(this)
    this.recognition.onerror  = this.handleError.bind(this)
    this.recognition.onend    = this.handleEnd.bind(this)

    // onstart: 録音が実際に開始されたタイミングで呼ばれる
    // 連打防止ロック（isProcessing）をここで解除する
    this.recognition.onstart = () => {
      this.isProcessing = false
    }

    this.isListening  = false
    this.startValue   = ""
    this.isProcessing = false

    // showToast() が生成するトーストの自動消去タイマーを保持する変数
    this.toastTimer = null
  }

  // ============================================================
  // disconnect(): コントローラーが DOM から切断されたとき自動で呼ばれる
  // ============================================================
  disconnect() {
    if (this.recognition && this.isListening) {
      this.recognition.abort()
      this.isListening = false
    }

    if (window.activeVoiceController === this) {
      window.activeVoiceController = null
    }

    // トーストのタイマーが残っていればクリアする
    if (this.toastTimer) {
      clearTimeout(this.toastTimer)
    }
  }

  // ============================================================
  // toggle(): 🎤ボタンがクリックされたとき呼ばれる
  // ============================================================
  toggle() {
    if (!this.recognition) {
      this.showToast("お使いのブラウザは音声入力に対応していません", "warning")
      return
    }

    // 連打防止: start()呼び出し中〜onstart発火までクリックを無視する
    if (this.isProcessing) return

    if (this.isListening) {
      this.stopRecording()
    } else {
      this.startRecording()
    }
  }

  // ============================================================
  // startRecording(): 音声認識を開始する
  // ============================================================
  startRecording() {
    if (!this.hasFieldTarget) return

    this.isProcessing = true

    // 複数フィールド同時録音の防止
    if (window.activeVoiceController &&
        window.activeVoiceController !== this &&
        window.activeVoiceController.isListening) {
      window.activeVoiceController.recognition.stop()
      window.activeVoiceController.isListening = false
      window.activeVoiceController.setButtonRecording(false)
    }

    window.activeVoiceController = this
    this.startValue = this.fieldTarget.value

    try {
      this.recognition.start()
      this.isListening = true
      this.setButtonRecording(true)
    } catch (error) {
      console.error("[VoiceInput] recognition.start() failed:", error)
      this.isListening = false
      this.setButtonRecording(false)
      this.showToast("音声入力の開始に失敗しました。もう一度お試しください", "warning")
      this.isProcessing = false
    }
  }

  // ============================================================
  // stopRecording(): 音声認識を停止する
  // ============================================================
  stopRecording() {
    this.recognition.stop()
  }

  // ============================================================
  // handleResult(event): 音声認識結果が得られたとき呼ばれる（リアルタイム追記の本体）
  // ============================================================
  handleResult(event) {
    if (!this.hasFieldTarget) return

    let finalTranscript   = ""
    let interimTranscript = ""

    for (let i = 0; i < event.results.length; i++) {
      const transcript = event.results[i][0].transcript

      if (event.results[i].isFinal) {
        finalTranscript += transcript
      } else {
        interimTranscript += transcript
      }
    }

    const hasNewSpeech = finalTranscript.length > 0 || interimTranscript.length > 0
    const needSeparator =
      this.startValue.length > 0 &&
      !this.startValue.endsWith("\n") &&
      hasNewSpeech

    const separator = needSeparator ? "\n" : ""

    // 話している最中からリアルタイムに反映する（interimTranscriptを含める）
    this.fieldTarget.value =
      this.startValue + separator + finalTranscript + interimTranscript

    this.fieldTarget.scrollTop = this.fieldTarget.scrollHeight
  }

  // ============================================================
  // handleError(event): 音声認識エラーが発生したとき呼ばれる
  // ============================================================
  handleError(event) {
    if (event.error === "aborted") return
    if (event.error === "no-speech") return

    let message = "音声入力でエラーが発生しました"

    switch (event.error) {
      case "not-allowed":
      case "service-not-allowed":
        message = "マイクへのアクセスを許可してください"
        break
      case "audio-capture":
        message = "マイクが見つかりません。接続を確認してください"
        break
      case "network":
        message = "ネットワークエラーが発生しました。接続を確認してください"
        break
    }

    this.showToast(message, "alert")

    this.isListening  = false
    this.isProcessing = false
    this.setButtonRecording(false)
  }

  // ============================================================
  // handleEnd(): 音声認識が終了したとき呼ばれる
  // ============================================================
  handleEnd() {
    this.isListening = false
    this.setButtonRecording(false)

    if (window.activeVoiceController === this) {
      window.activeVoiceController = null
    }
  }

  // ============================================================
  // setButtonRecording(isRecording): ボタンの見た目を切り替える
  // ============================================================
  setButtonRecording(isRecording) {
    if (!this.hasButtonTarget) return

    if (isRecording) {
      this.buttonTarget.setAttribute("aria-label", "音声入力を停止する")
      this.buttonTarget.classList.add(
        "animate-pulse", "bg-red-100", "border-red-400", "text-red-600"
      )
      this.buttonTarget.classList.remove("text-gray-500", "hover:bg-gray-50")
    } else {
      this.buttonTarget.setAttribute("aria-label", "音声入力を開始する")
      this.buttonTarget.classList.remove(
        "animate-pulse", "bg-red-100", "border-red-400", "text-red-600"
      )
      this.buttonTarget.classList.add("text-gray-500", "hover:bg-gray-50")
    }
  }

  // ============================================================
  // showToast(message, type): ボタン直下にインラインで警告を表示する
  // ============================================================
  //
  // 【設計方針】
  //   #flash-areaは使わない。🎤ボタンの直後に絶対配置(absolute)で
  //   メッセージボックスを挿入する。位置の基準となるposition:relativeは
  //   HTML側（親div）にあらかじめ用意されている前提で、JS側では
  //   style.positionを設定しない（レイアウト責務をHTML/CSS側に置くため）。
  showToast(message, type = "notice") {
    if (!this.hasButtonTarget) return

    // 既に同じコントローラー内に警告ボックスが表示中なら再利用する
    let toastBox = this.element.querySelector("[data-voice-inline-toast]")

    const styles = {
      notice:  { bg: "bg-blue-50",   border: "border-blue-300",   text: "text-blue-900",   icon: "✅" },
      alert:   { bg: "bg-red-50",    border: "border-red-300",    text: "text-red-900",    icon: "❌" },
      warning: { bg: "bg-yellow-50", border: "border-yellow-300", text: "text-yellow-900", icon: "⚠️" }
    }
    const style = styles[type] || styles.notice

    if (!toastBox) {
      // 警告ボックスが存在しない場合は新規生成する
      // position:relativeはHTML側のclass="relative"に依存するため
      // ここでは設定しない
      toastBox = document.createElement("div")
      toastBox.setAttribute("data-voice-inline-toast", "true")
      toastBox.setAttribute("role", "alert")
      toastBox.setAttribute("aria-live", "polite")

      // absolute: 親のrelativeを基準に浮かせて表示する
      // bottom-full: 親要素の直上に配置する（押したボタンのすぐ上に出すため）
      // right-0: 右端を親要素の右端に揃える
      // mb-2: ボタンとの間に少し余白を作る
      // z-50: 他要素より前面に表示する
      // w-64: 横幅を固定して読みやすくする
      // mb-2: ボタンとの間に少し余白を作る（topの場合のmt-2に相当）
      toastBox.className =
        "absolute bottom-full right-0 mb-2 z-50 w-64 px-3 py-2.5 rounded-lg border shadow-lg text-xs leading-relaxed"

      this.buttonTarget.insertAdjacentElement("afterend", toastBox)
    }

    // 内容とスタイルを更新する（新規・再利用どちらの場合も実行）
    toastBox.className =
      `absolute bottom-full right-0 mb-2 z-50 w-64 px-3 py-2.5 rounded-lg border shadow-lg text-xs leading-relaxed ${style.bg} ${style.border} ${style.text}`

    toastBox.innerHTML = `
      <div class="flex items-start gap-1.5">
        <span class="flex-shrink-0" aria-hidden="true">${style.icon}</span>
        <span class="flex-1">${this.escapeHtml(message)}</span>
        <button type="button"
                class="flex-shrink-0 opacity-60 hover:opacity-100"
                aria-label="閉じる">✕</button>
      </div>
    `

    // ✕ボタンのクリックハンドラー
    //
    // addEventListenerではなくonclickへの代入を使う:
    //   toastBoxを再利用するたびにaddEventListenerを呼ぶと
    //   クリックハンドラーが何重にも積み重なってしまう。
    //   onclickへの代入は常に1つだけのハンドラーに上書きされるため
    //   再利用しても重複登録が起こらない。
    const closeButton = toastBox.querySelector("button")
    closeButton.onclick = () => {
      toastBox.remove()
    }

    // 既存のタイマーをクリアしてから新しいタイマーをセットする
    if (this.toastTimer) {
      clearTimeout(this.toastTimer)
    }

    this.toastTimer = setTimeout(() => {
      if (toastBox && toastBox.parentNode) {
        toastBox.remove()
      }
    }, 4000)
  }

  // ============================================================
  // escapeHtml(text): XSS 対策のための HTML エスケープ
  // ============================================================
  escapeHtml(text) {
    const div = document.createElement("div")
    div.appendChild(document.createTextNode(text))
    return div.innerHTML
  }
}