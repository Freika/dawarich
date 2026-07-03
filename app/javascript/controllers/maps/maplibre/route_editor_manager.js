import maplibregl from "maplibre-gl"

export default class RouteEditorManager {
  constructor(controller, map, layerManager) {
    this.controller = controller
    this.map = map
    this.layerManager = layerManager
    this.api = controller.api

    this.enabled = false
    this.button = null
    this.panel = null
    this.statusEl = null
    this.pointsEl = null
    this.viaListEl = null
    this.presetNameInput = null
    this.presetSelectEl = null
    this.importFileInput = null

    this.mode = null
    this.startMarker = null
    this.endMarker = null
    this.viaMarkers = []

    this.previewSourceId = "route-editor-preview-source"
    this.previewLayerId = "route-editor-preview-layer"
    this.presetsStorageKey = "dawarich_route_editor_presets_v1"
    this.suspendPreviewRefresh = false

    this.handleMapClick = this.handleMapClick.bind(this)
    this.handleMapLoad = this.handleMapLoad.bind(this)
  }

  connect() {
    console.log("[RouteEditorManager] connected")
    this.addFloatingButton()
    this.addFloatingPanel()

    if (this.map.loaded()) {
      this.ensurePreviewLayer()
    } else {
      this.map.once("load", this.handleMapLoad)
    }

    this.loadPresetOptions()
    this.updateUI()
  }

  handleMapLoad() {
    this.ensurePreviewLayer()
    this.refreshPreviewRoute()
  }

  enable() {
    this.enabled = true
    this.updateUI()
    console.log("[RouteEditorManager] enabled")
  }

  disable() {
    this.enabled = false
    this.mode = null
    this.updateUI()
    console.log("[RouteEditorManager] disabled")
  }

  toggle() {
    if (this.enabled) {
      this.disable()
    } else {
      this.enable()
    }
  }

  addFloatingButton() {
    if (this.button) return

    this.button = document.createElement("button")
    this.button.type = "button"

    Object.assign(this.button.style, {
      position: "absolute",
      top: "12px",
      right: "12px",
      zIndex: "9999",
      padding: "8px 12px",
      borderRadius: "8px",
      border: "1px solid #ccc",
      background: "#fff",
      color: "#222",
      fontSize: "14px",
      fontWeight: "600",
      cursor: "pointer",
      boxShadow: "0 2px 8px rgba(0,0,0,0.15)",
    })

    this.button.addEventListener("click", () => this.toggle())
    document.body.appendChild(this.button)
  }

  addFloatingPanel() {
    if (this.panel) return

    this.panel = document.createElement("div")

    Object.assign(this.panel.style, {
      position: "absolute",
      top: "56px",
      right: "12px",
      zIndex: "9999",
      width: "320px",
      padding: "12px",
      borderRadius: "10px",
      border: "1px solid #d1d5db",
      background: "#ffffff",
      color: "#111827",
      boxShadow: "0 4px 14px rgba(0,0,0,0.18)",
      fontSize: "14px",
      display: "none",
      maxHeight: "70vh",
      overflowY: "auto",
    })

    const title = document.createElement("div")
    title.textContent = "Route Editor"
    Object.assign(title.style, {
      fontWeight: "700",
      marginBottom: "8px",
    })

    const subtitle = document.createElement("div")
    subtitle.textContent = "Click Add Start, Add End, or Add Via, then click on the map."
    Object.assign(subtitle.style, {
      fontSize: "12px",
      color: "#4b5563",
      marginBottom: "10px",
      lineHeight: "1.4",
    })

    const controls = document.createElement("div")
    Object.assign(controls.style, {
      display: "flex",
      flexWrap: "wrap",
      gap: "6px",
      marginBottom: "10px",
    })

    const addStartBtn = this.makePanelButton("Add Start")
    const addEndBtn = this.makePanelButton("Add End")
    const addViaBtn = this.makePanelButton("Add Via")
    const clearBtn = this.makePanelButton("Clear")

    addStartBtn.addEventListener("click", () => {
      this.mode = "add-start"
      this.setStatus("Click on the map to place the start point.")
    })

    addEndBtn.addEventListener("click", () => {
      this.mode = "add-end"
      this.setStatus("Click on the map to place the end point.")
    })

    addViaBtn.addEventListener("click", () => {
      this.mode = "add-via"
      this.setStatus("Click on the map to place a via point.")
    })

    clearBtn.addEventListener("click", () => {
      this.clearMarkers()
      this.mode = null
      this.setStatus("Editor points cleared.")
    })

    controls.appendChild(addStartBtn)
    controls.appendChild(addEndBtn)
    controls.appendChild(addViaBtn)
    controls.appendChild(clearBtn)

    const presetsSection = document.createElement("div")
    Object.assign(presetsSection.style, {
      background: "#f9fafb",
      border: "1px solid #e5e7eb",
      borderRadius: "8px",
      padding: "8px",
      marginBottom: "10px",
    })

    const presetsTitle = document.createElement("div")
    presetsTitle.textContent = "Presets"
    Object.assign(presetsTitle.style, {
      fontWeight: "600",
      fontSize: "13px",
      marginBottom: "6px",
    })

    this.presetNameInput = document.createElement("input")
    this.presetNameInput.type = "text"
    this.presetNameInput.placeholder = "Preset name"
    Object.assign(this.presetNameInput.style, {
      width: "100%",
      boxSizing: "border-box",
      padding: "7px 8px",
      marginBottom: "8px",
      borderRadius: "8px",
      border: "1px solid #d1d5db",
      fontSize: "13px",
      background: "#fff",
      color: "#111827",
    })

    this.presetSelectEl = document.createElement("select")
    Object.assign(this.presetSelectEl.style, {
      width: "100%",
      boxSizing: "border-box",
      padding: "7px 8px",
      marginBottom: "8px",
      borderRadius: "8px",
      border: "1px solid #d1d5db",
      fontSize: "13px",
      background: "#fff",
      color: "#111827",
    })

    this.presetSelectEl.addEventListener("change", () => {
      if (this.presetNameInput && this.presetSelectEl.value) {
        this.presetNameInput.value = this.presetSelectEl.value
      }
    })

    const presetButtons = document.createElement("div")
    Object.assign(presetButtons.style, {
      display: "flex",
      flexWrap: "wrap",
      gap: "6px",
      marginBottom: "8px",
    })

    const savePresetBtn = this.makePanelButton("Save Preset")
    const loadPresetBtn = this.makePanelButton("Load Preset")
    const renamePresetBtn = this.makePanelButton("Rename Preset")
    const deletePresetBtn = this.makePanelButton("Delete Preset")

    savePresetBtn.addEventListener("click", () => this.savePreset())
    loadPresetBtn.addEventListener("click", () => this.loadSelectedPreset())
    renamePresetBtn.addEventListener("click", () => this.renameSelectedPreset())
    deletePresetBtn.addEventListener("click", () => this.deleteSelectedPreset())

    presetButtons.appendChild(savePresetBtn)
    presetButtons.appendChild(loadPresetBtn)
    presetButtons.appendChild(renamePresetBtn)
    presetButtons.appendChild(deletePresetBtn)

    const transferButtons = document.createElement("div")
    Object.assign(transferButtons.style, {
      display: "flex",
      flexWrap: "wrap",
      gap: "6px",
    })

    const exportPresetsBtn = this.makePanelButton("Export Presets")
    const importPresetsBtn = this.makePanelButton("Import Presets")

    exportPresetsBtn.addEventListener("click", () => this.exportPresets())
    importPresetsBtn.addEventListener("click", () => this.triggerImportPresets())

    transferButtons.appendChild(exportPresetsBtn)
    transferButtons.appendChild(importPresetsBtn)

    this.importFileInput = document.createElement("input")
    this.importFileInput.type = "file"
    this.importFileInput.accept = ".json,application/json"
    this.importFileInput.style.display = "none"
    this.importFileInput.addEventListener("change", (event) => this.importPresetsFromFile(event))

    presetsSection.appendChild(presetsTitle)
    presetsSection.appendChild(this.presetNameInput)
    presetsSection.appendChild(this.presetSelectEl)
    presetsSection.appendChild(presetButtons)
    presetsSection.appendChild(transferButtons)
    presetsSection.appendChild(this.importFileInput)

    this.statusEl = document.createElement("div")
    Object.assign(this.statusEl.style, {
      fontSize: "12px",
      color: "#374151",
      background: "#f3f4f6",
      padding: "8px",
      borderRadius: "8px",
      lineHeight: "1.4",
      marginBottom: "10px",
    })

    this.pointsEl = document.createElement("div")
    Object.assign(this.pointsEl.style, {
      fontSize: "12px",
      color: "#374151",
      background: "#f9fafb",
      padding: "8px",
      borderRadius: "8px",
      lineHeight: "1.5",
      border: "1px solid #e5e7eb",
      marginBottom: "10px",
    })

    const viaTitle = document.createElement("div")
    viaTitle.textContent = "Via Points"
    Object.assign(viaTitle.style, {
      fontWeight: "600",
      fontSize: "13px",
      marginBottom: "6px",
    })

    this.viaListEl = document.createElement("div")
    Object.assign(this.viaListEl.style, {
      display: "flex",
      flexDirection: "column",
      gap: "6px",
    })

    this.panel.appendChild(title)
    this.panel.appendChild(subtitle)
    this.panel.appendChild(controls)
    this.panel.appendChild(presetsSection)
    this.panel.appendChild(this.statusEl)
    this.panel.appendChild(this.pointsEl)
    this.panel.appendChild(viaTitle)
    this.panel.appendChild(this.viaListEl)

    document.body.appendChild(this.panel)
  }

  makePanelButton(label) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.textContent = label

    Object.assign(btn.style, {
      padding: "6px 10px",
      borderRadius: "8px",
      border: "1px solid #d1d5db",
      background: "#fff",
      color: "#111827",
      fontSize: "13px",
      fontWeight: "600",
      cursor: "pointer",
    })

    return btn
  }

  updateUI() {
    if (this.button) {
      this.button.textContent = this.enabled ? "Route Editor: On" : "Route Editor: Off"
      this.button.style.background = this.enabled ? "#d1fae5" : "#fff"
      this.button.style.borderColor = this.enabled ? "#10b981" : "#ccc"
    }

    if (this.panel) {
      this.panel.style.display = this.enabled ? "block" : "none"
    }

    if (this.map) {
      this.map.off("click", this.handleMapClick)
      if (this.enabled) this.map.on("click", this.handleMapClick)
    }

    this.setStatus(this.enabled ? "Route editor active" : "Route editor inactive")
    this.updatePointsSummary()
    this.renderViaList()
    this.refreshPreviewRoute()
  }

  handleMapClick(event) {
    try {
      if (!this.enabled || !this.mode) return

      const lngLat = event.lngLat

      if (this.mode === "add-start") {
        this.placeStartMarker(lngLat)
        this.mode = null
        this.setStatus("Start point placed.")
        return
      }

      if (this.mode === "add-end") {
        this.placeEndMarker(lngLat)
        this.mode = null
        this.setStatus("End point placed.")
        return
      }

      if (this.mode === "add-via") {
        this.placeViaMarker(lngLat)
        this.mode = null
        this.setStatus("Via point placed.")
      }
    } catch (error) {
      console.error("[RouteEditorManager] map click failed", error)
      this.setStatus(`Placement failed: ${error.message}`)
    }
  }

  placeStartMarker(lngLat) {
    if (!this.startMarker) {
      this.startMarker = new maplibregl.Marker({ color: "green", draggable: true })
        .setLngLat(lngLat)
        .addTo(this.map)

      this.startMarker.on("dragend", () => {
        this.setStatus("Start point moved.")
        this.updatePointsSummary()
        this.refreshPreviewRoute()
      })
    } else {
      this.startMarker.setLngLat(lngLat)
    }

    this.updatePointsSummary()
    this.refreshPreviewRoute()
  }

  placeEndMarker(lngLat) {
    if (!this.endMarker) {
      this.endMarker = new maplibregl.Marker({ color: "red", draggable: true })
        .setLngLat(lngLat)
        .addTo(this.map)

      this.endMarker.on("dragend", () => {
        this.setStatus("End point moved.")
        this.updatePointsSummary()
        this.refreshPreviewRoute()
      })
    } else {
      this.endMarker.setLngLat(lngLat)
    }

    this.updatePointsSummary()
    this.refreshPreviewRoute()
  }

  placeViaMarker(lngLat) {
    const marker = new maplibregl.Marker({ color: "orange", draggable: true })
      .setLngLat(lngLat)
      .addTo(this.map)

    marker.on("dragend", () => {
      this.setStatus("Via point moved.")
      this.updatePointsSummary()
      this.renderViaList()
      this.refreshPreviewRoute()
    })

    this.viaMarkers.push(marker)
    this.updatePointsSummary()
    this.renderViaList()
    this.refreshPreviewRoute()
  }

  removeViaMarker(index) {
    const marker = this.viaMarkers[index]
    if (!marker) return

    marker.remove()
    this.viaMarkers.splice(index, 1)

    this.setStatus(`Via ${index + 1} removed.`)
    this.updatePointsSummary()
    this.renderViaList()
    this.refreshPreviewRoute()
  }

  clearMarkers() {
    if (this.startMarker) {
      this.startMarker.remove()
      this.startMarker = null
    }

    if (this.endMarker) {
      this.endMarker.remove()
      this.endMarker = null
    }

    this.viaMarkers.forEach((marker) => marker.remove())
    this.viaMarkers = []

    this.updatePointsSummary()
    this.renderViaList()
    this.clearPreviewRoute()
  }

  updatePointsSummary() {
    if (!this.pointsEl) return

    const startText = this.startMarker
      ? this.formatLngLat(this.startMarker.getLngLat())
      : "Not set"

    const endText = this.endMarker
      ? this.formatLngLat(this.endMarker.getLngLat())
      : "Not set"

    const viaCount = this.viaMarkers.length

    this.pointsEl.innerHTML = `
      <strong>Start:</strong> ${startText}<br>
      <strong>End:</strong> ${endText}<br>
      <strong>Via count:</strong> ${viaCount}
    `
  }

  renderViaList() {
    if (!this.viaListEl) return

    this.viaListEl.innerHTML = ""

    if (this.viaMarkers.length === 0) {
      const empty = document.createElement("div")
      empty.textContent = "No via points"
      Object.assign(empty.style, {
        fontSize: "12px",
        color: "#6b7280",
        background: "#f9fafb",
        padding: "8px",
        borderRadius: "8px",
        border: "1px solid #e5e7eb",
      })
      this.viaListEl.appendChild(empty)
      return
    }

    this.viaMarkers.forEach((marker, index) => {
      const row = document.createElement("div")
      Object.assign(row.style, {
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: "8px",
        background: "#f9fafb",
        padding: "8px",
        borderRadius: "8px",
        border: "1px solid #e5e7eb",
      })

      const text = document.createElement("div")
      text.innerHTML = `<strong>Via ${index + 1}</strong><br>${this.formatLngLat(marker.getLngLat())}`
      Object.assign(text.style, {
        fontSize: "12px",
        lineHeight: "1.4",
        color: "#374151",
      })

      const removeBtn = document.createElement("button")
      removeBtn.type = "button"
      removeBtn.textContent = "Remove"
      Object.assign(removeBtn.style, {
        padding: "5px 8px",
        borderRadius: "8px",
        border: "1px solid #d1d5db",
        background: "#fff",
        color: "#111827",
        fontSize: "12px",
        fontWeight: "600",
        cursor: "pointer",
        flexShrink: "0",
      })

      removeBtn.addEventListener("click", () => this.removeViaMarker(index))

      row.appendChild(text)
      row.appendChild(removeBtn)
      this.viaListEl.appendChild(row)
    })
  }

  formatLngLat(lngLat) {
    return `${lngLat.lat.toFixed(5)}, ${lngLat.lng.toFixed(5)}`
  }

  setStatus(message) {
    if (!this.statusEl) return
    this.statusEl.textContent = message
  }

  serializeLngLat(lngLat) {
    return {
      lat: lngLat.lat,
      lng: lngLat.lng,
    }
  }

  buildPreviewLocations() {
    const locations = []

    if (this.startMarker) {
      const ll = this.startMarker.getLngLat()
      locations.push({ lat: ll.lat, lon: ll.lng, type: "break" })
    }

    this.viaMarkers.forEach((marker) => {
      const ll = marker.getLngLat()
      locations.push({ lat: ll.lat, lon: ll.lng, type: "through" })
    })

    if (this.endMarker) {
      const ll = this.endMarker.getLngLat()
      locations.push({ lat: ll.lat, lon: ll.lng, type: "break" })
    }

    return locations
  }

  getPresetData() {
    return {
      start: this.startMarker ? this.serializeLngLat(this.startMarker.getLngLat()) : null,
      end: this.endMarker ? this.serializeLngLat(this.endMarker.getLngLat()) : null,
      vias: this.viaMarkers.map((marker) => this.serializeLngLat(marker.getLngLat())),
      savedAt: new Date().toISOString(),
    }
  }

  getPresets() {
    try {
      const raw = window.localStorage.getItem(this.presetsStorageKey)
      if (!raw) return {}
      const parsed = JSON.parse(raw)
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
    } catch (error) {
      console.error("[RouteEditorManager] failed to read presets", error)
      this.setStatus("Could not read saved presets.")
      return {}
    }
  }

  setPresets(presets) {
    try {
      window.localStorage.setItem(this.presetsStorageKey, JSON.stringify(presets))
      return true
    } catch (error) {
      console.error("[RouteEditorManager] failed to save presets", error)
      this.setStatus("Could not save presets.")
      return false
    }
  }

  loadPresetOptions(selectedName = "") {
    if (!this.presetSelectEl) return

    const presets = this.getPresets()
    const names = Object.keys(presets).sort((a, b) => a.localeCompare(b))

    this.presetSelectEl.innerHTML = ""

    const placeholder = document.createElement("option")
    placeholder.value = ""
    placeholder.textContent = names.length ? "Select saved preset" : "No saved presets"
    this.presetSelectEl.appendChild(placeholder)

    names.forEach((name) => {
      const option = document.createElement("option")
      option.value = name
      option.textContent = name
      if (name === selectedName) {
        option.selected = true
      }
      this.presetSelectEl.appendChild(option)
    })

    if (selectedName && this.presetNameInput) {
      this.presetNameInput.value = selectedName
    }
  }

  getSelectedPresetName() {
    return (
      (this.presetSelectEl && this.presetSelectEl.value) ||
      ""
    ).trim()
  }

  getEnteredPresetName() {
    return (
      (this.presetNameInput && this.presetNameInput.value) ||
      ""
    ).trim()
  }

  savePreset() {
    const name = this.getEnteredPresetName()

    if (!name) {
      this.setStatus("Enter a preset name first.")
      return
    }

    const hasAnyPoints = this.startMarker || this.endMarker || this.viaMarkers.length > 0
    if (!hasAnyPoints) {
      this.setStatus("Add route points before saving a preset.")
      return
    }

    const presets = this.getPresets()
    presets[name] = this.getPresetData()

    if (!this.setPresets(presets)) return

    this.loadPresetOptions(name)
    this.setStatus(`Preset saved: ${name}`)
  }

  loadSelectedPreset() {
    const selectedName = this.getSelectedPresetName() || this.getEnteredPresetName()

    if (!selectedName) {
      this.setStatus("Choose a preset to load.")
      return
    }

    const presets = this.getPresets()
    const preset = presets[selectedName]

    if (!preset) {
      this.setStatus(`Preset not found: ${selectedName}`)
      return
    }

    this.applyPresetData(preset)
    if (this.presetNameInput) {
      this.presetNameInput.value = selectedName
    }
    if (this.presetSelectEl) {
      this.presetSelectEl.value = selectedName
    }
    this.setStatus(`Preset loaded: ${selectedName}`)
  }

  renameSelectedPreset() {
    const oldName = this.getSelectedPresetName()
    const newName = this.getEnteredPresetName()

    if (!oldName) {
      this.setStatus("Choose a preset to rename.")
      return
    }

    if (!newName) {
      this.setStatus("Enter the new preset name.")
      return
    }

    const presets = this.getPresets()

    if (!presets[oldName]) {
      this.setStatus(`Preset not found: ${oldName}`)
      return
    }

    if (oldName === newName) {
      this.setStatus("Preset name is unchanged.")
      return
    }

    if (presets[newName]) {
      this.setStatus(`A preset already exists with that name: ${newName}`)
      return
    }

    presets[newName] = presets[oldName]
    delete presets[oldName]

    if (!this.setPresets(presets)) return

    this.loadPresetOptions(newName)
    if (this.presetNameInput) {
      this.presetNameInput.value = newName
    }
    if (this.presetSelectEl) {
      this.presetSelectEl.value = newName
    }

    this.setStatus(`Preset renamed: ${oldName} → ${newName}`)
  }

  deleteSelectedPreset() {
    const selectedName = this.getSelectedPresetName() || this.getEnteredPresetName()

    if (!selectedName) {
      this.setStatus("Choose a preset to delete.")
      return
    }

    const presets = this.getPresets()
    if (!presets[selectedName]) {
      this.setStatus(`Preset not found: ${selectedName}`)
      return
    }

    delete presets[selectedName]

    if (!this.setPresets(presets)) return

    this.loadPresetOptions()
    if (this.presetNameInput) {
      this.presetNameInput.value = ""
    }
    this.setStatus(`Preset deleted: ${selectedName}`)
  }

  exportPresets() {
    const presets = this.getPresets()
    const names = Object.keys(presets)

    if (!names.length) {
      this.setStatus("No presets to export.")
      return
    }

    const payload = {
      version: 1,
      exportedAt: new Date().toISOString(),
      presets: presets,
    }

    const blob = new Blob([JSON.stringify(payload, null, 2)], {
      type: "application/json",
    })

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-")
    const url = window.URL.createObjectURL(blob)
    const link = document.createElement("a")

    link.href = url
    link.download = `dawarich-route-presets-${timestamp}.json`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)

    window.setTimeout(() => {
      window.URL.revokeObjectURL(url)
    }, 1000)

    this.setStatus(`Exported ${names.length} preset(s).`)
  }

  triggerImportPresets() {
    if (!this.importFileInput) return
    this.importFileInput.value = ""
    this.importFileInput.click()
  }

  importPresetsFromFile(event) {
    const file = event.target.files && event.target.files[0]
    if (!file) return

    const reader = new FileReader()

    reader.onload = () => {
      try {
        const text = typeof reader.result === "string" ? reader.result : ""
        const parsed = JSON.parse(text)

        let importedPresets = parsed
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed) && parsed.presets) {
          importedPresets = parsed.presets
        }

        if (
          !importedPresets ||
          typeof importedPresets !== "object" ||
          Array.isArray(importedPresets)
        ) {
          throw new Error("Invalid preset JSON format")
        }

        const existingPresets = this.getPresets()
        const importedNames = Object.keys(importedPresets)

        if (!importedNames.length) {
          throw new Error("Imported file contains no presets")
        }

        let overwrittenCount = 0
        importedNames.forEach((name) => {
          if (existingPresets[name]) {
            overwrittenCount += 1
          }
        })

        const mergedPresets = {
          ...existingPresets,
          ...importedPresets,
        }

        if (!this.setPresets(mergedPresets)) return

        const selectedName = importedNames[0]
        this.loadPresetOptions(selectedName)
        if (this.presetNameInput) {
          this.presetNameInput.value = selectedName
        }

        this.setStatus(
          `Imported ${importedNames.length} preset(s)` +
            (overwrittenCount ? `, overwrote ${overwrittenCount}.` : "."),
        )
      } catch (error) {
        console.error("[RouteEditorManager] failed to import presets", error)
        this.setStatus(`Import failed: ${error.message}`)
      }
    }

    reader.onerror = () => {
      console.error("[RouteEditorManager] failed to read import file")
      this.setStatus("Import failed: could not read file.")
    }

    reader.readAsText(file)
  }

  applyPresetData(preset) {
    this.suspendPreviewRefresh = true

    this.clearMarkers()

    if (preset && preset.start) {
      this.placeStartMarker({ lng: preset.start.lng, lat: preset.start.lat })
    }

    if (preset && Array.isArray(preset.vias)) {
      preset.vias.forEach((via) => {
        this.placeViaMarker({ lng: via.lng, lat: via.lat })
      })
    }

    if (preset && preset.end) {
      this.placeEndMarker({ lng: preset.end.lng, lat: preset.end.lat })
    }

    this.suspendPreviewRefresh = false
    this.updatePointsSummary()
    this.renderViaList()
    this.refreshPreviewRoute()
  }

  ensurePreviewLayer() {
    if (!this.map.getSource(this.previewSourceId)) {
      this.map.addSource(this.previewSourceId, {
        type: "geojson",
        data: {
          type: "FeatureCollection",
          features: [],
        },
      })
    }

    if (!this.map.getLayer(this.previewLayerId)) {
      this.map.addLayer({
        id: this.previewLayerId,
        type: "line",
        source: this.previewSourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": "#f97316",
          "line-width": 5,
          "line-opacity": 1,
          "line-dasharray": [2, 1],
        },
      })
    }
  }

  setPreviewGeoJSON(geojson) {
    if (!this.map) return

    if (!this.map.getSource(this.previewSourceId) || !this.map.getLayer(this.previewLayerId)) {
      this.ensurePreviewLayer()
    }

    const source = this.map.getSource(this.previewSourceId)
    if (source && source.setData) {
      source.setData(geojson)
    }
  }

  async refreshPreviewRoute() {
    if (!this.map || this.suspendPreviewRefresh) return

    const locations = this.buildPreviewLocations()

    if (locations.length < 2) {
      this.clearPreviewRoute()
      return
    }

    try {
      this.setStatus("Fetching snapped preview route...")

      const response = await fetch("/api/v1/route_editor/preview", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          api_key: this.controller.apiKeyValue,
          locations: locations,
        }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || "Preview request failed")
      }

      this.setPreviewGeoJSON(data)
      this.setStatus("Snapped preview route updated.")
    } catch (error) {
      console.error("[RouteEditorManager] preview fetch failed", error)
      this.setStatus(`Preview failed: ${error.message}`)
      this.clearPreviewRoute()
    }
  }

  clearPreviewRoute() {
    this.setPreviewGeoJSON({
      type: "FeatureCollection",
      features: [],
    })
  }

  getRoutesLayer() {
    return this.layerManager?.getLayer("routes")
  }

  getPointsLayer() {
    return this.layerManager?.getLayer("points")
  }
}


