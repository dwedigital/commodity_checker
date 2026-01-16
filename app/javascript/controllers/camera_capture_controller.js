import { Controller } from "@hotwired/stimulus"

// Camera capture controller for photo-based product lookup
// Handles webcam/phone camera access, capture, and file upload fallback
export default class extends Controller {
  static targets = [
    "video",           // Video element for camera preview
    "canvas",          // Hidden canvas for capturing frame
    "preview",         // Image element to show captured photo
    "fileInput",       // Hidden file input for form submission
    "cameraSection",   // Section containing camera UI
    "previewSection",  // Section containing captured image
    "fallbackSection", // Section for file upload fallback
    "startButton",     // Button to start camera
    "captureButton",   // Button to capture photo
    "retakeButton",    // Button to retake photo
    "submitButton",    // Button to submit form
    "switchButton",    // Button to switch camera
    "errorMessage",    // Error message container div
    "errorText"        // Error message text p element
  ]

  static values = {
    facingMode: { type: String, default: "environment" }, // environment = back camera, user = front
    submitUrl: { type: String, default: "/product_lookups/create_from_photo" }
  }

  connect() {
    this.stream = null
    this.capturedBlob = null
    this.capturedFromCamera = false
    this.checkCameraSupport()
  }

  disconnect() {
    this.stopCamera()
  }

  checkCameraSupport() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      this.showFallback("Camera not supported on this device")
      return
    }
  }

  async startCamera() {
    try {
      // Stop any existing stream
      this.stopCamera()

      const constraints = {
        video: {
          facingMode: this.facingModeValue,
          width: { ideal: 1280 },
          height: { ideal: 720 }
        },
        audio: false
      }

      this.stream = await navigator.mediaDevices.getUserMedia(constraints)
      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()

      // Show camera UI
      this.cameraSectionTarget.classList.remove("hidden")
      this.previewSectionTarget.classList.add("hidden")
      this.fallbackSectionTarget.classList.add("hidden")

      // Show capture button, hide start button
      if (this.hasStartButtonTarget) {
        this.startButtonTarget.classList.add("hidden")
      }
      this.captureButtonTarget.classList.remove("hidden")

      // Check if we can switch cameras (mobile devices)
      this.checkMultipleCameras()

      // Hide any error messages
      if (this.hasErrorMessageTarget) {
        this.errorMessageTarget.classList.add("hidden")
      }
    } catch (error) {
      console.error("Camera error:", error)
      this.handleCameraError(error)
    }
  }

  async checkMultipleCameras() {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices()
      const videoDevices = devices.filter(device => device.kind === "videoinput")

      // Show switch button only if multiple cameras available
      if (this.hasSwitchButtonTarget) {
        if (videoDevices.length > 1) {
          this.switchButtonTarget.classList.remove("hidden")
        } else {
          this.switchButtonTarget.classList.add("hidden")
        }
      }
    } catch (error) {
      console.log("Could not enumerate devices:", error)
    }
  }

  switchCamera() {
    this.facingModeValue = this.facingModeValue === "environment" ? "user" : "environment"
    this.startCamera()
  }

  capturePhoto() {
    if (!this.stream) return

    const video = this.videoTarget
    const canvas = this.canvasTarget

    // Set canvas size to match video
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight

    // Draw video frame to canvas
    const ctx = canvas.getContext("2d")
    ctx.drawImage(video, 0, 0)

    // Convert canvas to blob
    canvas.toBlob((blob) => {
      this.capturedBlob = blob
      this.capturedFromCamera = true

      // Show preview
      const url = URL.createObjectURL(blob)
      this.previewTarget.src = url

      // Switch to preview mode
      this.cameraSectionTarget.classList.add("hidden")
      this.previewSectionTarget.classList.remove("hidden")

      // Stop camera to save battery
      this.stopCamera()

      // Show submit button
      if (this.hasSubmitButtonTarget) {
        this.submitButtonTarget.classList.remove("hidden")
      }
    }, "image/jpeg", 0.9)
  }

  retake() {
    // Clear preview
    this.previewTarget.src = ""
    this.capturedBlob = null
    this.capturedFromCamera = false

    // Clear file input
    this.fileInputTarget.value = ""

    // Hide submit button
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.classList.add("hidden")
    }

    // Restart camera
    this.startCamera()
  }

  // Handle form submission - use fetch for camera captures
  async submitForm(event) {
    // If captured from camera, we need to submit via fetch
    if (this.capturedFromCamera && this.capturedBlob) {
      event.preventDefault()

      // Disable submit button and show loading state
      if (this.hasSubmitButtonTarget) {
        this.submitButtonTarget.disabled = true
        this.submitButtonTarget.textContent = "Uploading..."
      }

      try {
        const formData = new FormData()
        formData.append("product_lookup[product_image]", this.capturedBlob, "product_photo.jpg")

        // Get CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

        const response = await fetch(this.submitUrlValue, {
          method: "POST",
          headers: {
            "X-CSRF-Token": csrfToken,
            "Accept": "text/html,application/xhtml+xml"
          },
          body: formData
        })

        if (response.redirected) {
          // Follow the redirect
          window.location.href = response.url
        } else if (response.ok) {
          // Parse response to find redirect or handle success
          const html = await response.text()
          // Check if we got redirected via Turbo
          if (response.headers.get("Location")) {
            window.location.href = response.headers.get("Location")
          } else {
            // Reload the page or redirect to index
            window.location.href = "/product_lookups"
          }
        } else {
          throw new Error("Upload failed")
        }
      } catch (error) {
        console.error("Submit error:", error)
        alert("Failed to upload image. Please try again.")

        // Re-enable submit button
        if (this.hasSubmitButtonTarget) {
          this.submitButtonTarget.disabled = false
          this.submitButtonTarget.textContent = "Analyze Product"
        }
      }
    }
    // If from file picker, let normal form submission happen
  }

  handleCameraError(error) {
    let message = "Could not access camera"

    if (error.name === "NotAllowedError" || error.name === "PermissionDeniedError") {
      message = "Camera permission denied. Please allow camera access and try again."
    } else if (error.name === "NotFoundError" || error.name === "DevicesNotFoundError") {
      message = "No camera found on this device"
    } else if (error.name === "NotReadableError" || error.name === "TrackStartError") {
      message = "Camera is already in use by another application"
    } else if (error.name === "OverconstrainedError") {
      message = "Camera doesn't support the requested settings"
    }

    this.showFallback(message)
  }

  showFallback(errorMessage = null) {
    this.cameraSectionTarget.classList.add("hidden")
    this.previewSectionTarget.classList.add("hidden")
    this.fallbackSectionTarget.classList.remove("hidden")

    if (errorMessage && this.hasErrorMessageTarget && this.hasErrorTextTarget) {
      this.errorTextTarget.textContent = errorMessage
      this.errorMessageTarget.classList.remove("hidden")
    }
  }

  // Handle file selection via fallback input
  fileSelected(event) {
    const file = event.target.files[0]
    if (!file) return

    // Validate file type
    if (!file.type.startsWith("image/")) {
      alert("Please select an image file")
      event.target.value = ""
      return
    }

    // Not from camera, will use normal form submission
    this.capturedFromCamera = false
    this.capturedBlob = null

    // Show preview
    const url = URL.createObjectURL(file)
    this.previewTarget.src = url
    this.previewSectionTarget.classList.remove("hidden")
    this.fallbackSectionTarget.classList.add("hidden")

    // Show submit button
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.classList.remove("hidden")
    }
  }

  useFallback() {
    this.stopCamera()
    this.showFallback()
  }

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop())
      this.stream = null
    }
    if (this.hasVideoTarget) {
      this.videoTarget.srcObject = null
    }
  }
}
