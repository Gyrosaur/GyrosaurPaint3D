# GyrosaurPaint3D — Development Log

## v0.1 — Projektin alkutila (aiempi sessio)
- Duplikaatti GyroAR3DPaint-projektista kansioon `GyrosaurPaint3D_ap`
- Olemassa: Real World AR, Brush Studio, alkuvalikko (ModeSelectionView)

## v0.2 — Still Mode -pohja (aiempi sessio)
**Tehty:**
- `StillModeView.swift` — uusi mode ilman touch-piirtoa
- `WatchMotionManager.swift` — WCSession, gyro + crown → hue
- `FaceInputManager.swift` — ARKit face tracking (suun/leuan/kulmakarvan data)
- `MotionRecorder.swift` — Gyrosaur Timeline `.gmt` JSON-formaatti, record/playback
- `ModeSelectionView.swift` — Still Mode lisätty kolmanneksi
- `InputSettingsManager.swift` — Watch ja Face-kanavat, ARCameraParams
- `DrawingEngine.swift` — `endDrawing()` alias
- `GyroAR3DPaintApp.swift` — Still Mode reititys
- `project.pbxproj` — kaikki tiedostot + WatchConnectivity.framework

## v0.3 — Controller gate + AirPods fix (aiempi sessio)
**Tehty:**
- Xbox RT → draw gate Still Modessa (toggle / pitkä paina = hold-mode)
- `FaceInputManager.start()` pois automaattistartuista → ei enää kaappaa ARKitin sessiota
- Takakamera pysyy hengissä
- `WatchApp_README_AddToWatchTarget.swift` — Watch Extension koodi valmiina

## v0.4 — Arkkitehtuurikorjaus + oikea tatti (aiempi sessio)
**Tehty:**
- `StillSensorBridge` — `@MainActor ObservableObject` joka ohittaa SwiftUI update-syklin
- Attitude-data kulkee suoraan sensoriCB → bridge → coordinator (60Hz)
- `StillDrawSource.rightStick` — Xbox oikea tatti piirtosuunnaksi
- Aloituspaikka-ankuri: tallennetaan koordinaateista kun gate avautuu
- AirPods-moodissa aloituspiste pään suunnan mukainen (headRotationMatrix)
- Coordinator muutettu `@MainActor` + `assumeIsolated` → ei turhia Task-allokointeja

## v0.5 — Input settings rakenneuudistus (aiempi sessio)
**Tehty:**
- `InputSettingsManager` rakenne käännetty: toiminto ensin → lähde valitaan sille
- Kaikki Watch + Face-kanavat poistettu valikosta
- Oletukset: kaikki None paitsi Opacity → Left Slider
- Draw gate `drawGateSource: InputChannel` lisätty
- `InputSettingsView` + `StillInputSettingsView` uusittu — toiminto otsikkona, lähde valitsimessa
- Käytössä oleva lähde merkitty `⚬`-merkillä muissa valinnoissa
- LT/RT gate-logiikka korjattu: rising/falling edge omalla tilamuuttujalla
- `MappingRow` + `GateSourceRow` komponentit
- Draw distance max 1/4 (0.5m aiemman 2m sijaan)

---

## v0.6 — UI-korjaukset, LT hold-mode, swipe-paneeli, menu-nappi (tämä sessio)

### Suunnitelma:
1. Draw direction -nappi toimimaan oikein (nyt jumissa phone gyroon)
2. Draw direction omaksi osiokseen StillInputSettingsViewssä (ei enää vain floating nappi)
3. LT = piirto vain kun pohjassa (ei toggle-logiikkaa LT:lle)
4. Siniset pallot / kolme ympyrää -ikonit toimimaan (brush + color popovers)
5. Xbox menu-nappi (kolme viivaa) = hide/show UI
6. Oikean reunan swipe → transparentti input-pikavalikko
7. Taustanvalintanappi (AR / musta / valkoinen)

### Tehty:
- `StillModeView.swift` kirjoitettu kokonaan uudelleen selkeämmällä rakenteella
- Draw direction -valinta siirretty `StillInputSettingsView`n ensimmäiseksi osioksi (Picker .inline) — ei enää popup-nappi joka ei toiminut
- Draw direction päivittyy nyt oikeasti: `@Binding var drawSource` kulkee settingsihin asti
- LT = hold-only, piirto vain kun nappi pohjassa (ei toggle-logiikkaa)
- RT = toggle / hold-mode (pitkä paina ≥0.6s → hold-mode)
- Xbox menu-nappi (kolme viivaa) = toggle hideUI
- Oikean reunan swipe-paneeli: draw direction, gate, background — kaikki pikavalinnat yhdessä näkymässä
- Taustanvalinta: AR camera / musta / valkoinen / vihreä (käyttää olemassa olevaa `BackgroundMode`)
- Brush type -picker: scrollattava grid kaikista brusheista
- Color/opacity/size -picker: väripallot + sliderit
- Poistettu turhat `StillBackground`-enum-duplikaatti — käytetään `BackgroundMode`:a
- `BackgroundMode`-extensio: `.icon`, `.tintColor`, `.next()`
- `StillInputSettingsView` käyttää `@Binding var drawSource` joten valinta todella päivittyy
- `StillARCanvas` + Coordinator kirjoitettu puhtaasti, `@MainActor` + `assumeIsolated`
- Draw distance max 0.5m (aiemman 2m sijaan)


## v0.7 — Vasemman reunan ikonit → yksi nappi; Tentacle live-värinohjaus (tämä sessio)

### Suunnitelma:
1. ContentView: vasemman reunan 8 ikonia → yksi "⋯" nappi joka avaa popoeverin niistä
2. Tentacle brush: live-värinohjaus piirron aikana
   - Xbox tatti tai mikrofoni pitch → hue muutos reaaliajassa (per-point väri)
   - Kaksi väriäärireytä (A ja B) joiden välillä liikutaan
   - Threshold + release-aika
   - Toteutetaan DrawingEngine:en TentacleColorController-rakenteena
   - StrokeRenderer päivitetään käyttämään per-point dynaamista hue-arvoa

### Tehty:

- `recordingStatusIcons` → yksi `⋯`-nappi + `statusPanelView` popover
  - Popoverissa: performance, controller, AirPods, input source, camera color, input settings, MIDI
- `TentacleColorController.swift` — uusi tiedosto
  - Lähde: Xbox Right Stick X/Y, Mic Pitch, Mic Amplitude, tai Off
  - Kaksi väriäärireytä (A ja B), threshold, release-nopeus
  - `update()` per-tick: nopea ylöspäin, pehmeä release alaspäin
  - Väri-interpolaatio lyhintä reittiä hue-ympyrässä
- `DrawingEngine` — `tentacleColor: TentacleColorController` + `StrokePoint.tentacleHue`
- `DrawingEngine.addPoint()` — tallentaa `tentacleColor.currentT` tentacle-brushille per-pisteeseen
- `ARViewContainer.frameUpdate()` — `tentacleColor.update()` per-tick
- `StrokeRenderer.makeTentacle()` — per-segment mesh omine väreineen, groupSize=4
  - `tentacleUIColor()` — interpoloi base-väristä komplementtiväriin hue-kierrolla
- `ContentView` — Tentacle-asetusnappi (waveform.path.ecg) ilmestyy kun tentacle valittuna
- `InputSettingsView` — `TentacleColorSettingsView` lisätty (source, värit A/B, threshold, release, live preview)
- `pbxproj` — `TentacleColorController.swift` lisätty Build + FileRef + Group + Sources


## v0.8 — Tentacle live color oikein (tämä sessio)

### Mikä meni pieleen v0.7:ssa:
- TentacleColorController oli väärä lähestymistapa — se oli erillinen järjestelmä
- Oikea tentacle-brush on BrushType.tentacle (enum), neljäs brush-valikossa
- Ongelma oli että makeTentacle() rakensi yhdistelmämeshin yhdellä värillä eikä hyödyntänyt ColorMode:a per-pisteessä

### Tehty v0.8:
- `TentacleColorController.swift` poistettu kokonaan, kaikki viittaukset siivottu
- `BrushDefinition.ColorMode` laajennettu:
  - `liveSource: LiveColorSource` — Off / Xbox Stick X/Y / LT / RT / Mic Pitch / Mic Amplitude
  - `liveHueA`, `liveHueB` — värit A ja B (hue 0–1)
  - `liveSaturation`, `liveBrightness` — saturaatio ja kirkkaus molemmille
  - `liveThreshold` — kynnys alle jonka = väri A
  - `liveRelease` — palautumisnopeus per frame (pehmeä alas, nopea ylös)
- `DrawingEngine.updateLiveColor()` — per-tick, nopea ylöspäin / pehmeä release alaspäin
- `DrawingEngine.addPoint()` — tallentaa `liveColorT` gradientValue-kenttään kun preset + liveSource aktiiivisena
- `ARViewContainer.frameUpdate()` — kutsuu `updateLiveColor()` per tick
- `StrokeRenderer.applyColorMode()` — live-interpolaatio hue A→B lyhintä reittiä
- `StrokeRenderer.makeTentacle()` — korjattu: per-3-pisteen segmentti, käyttää `pointColor()` + ColorMode
- `BrushStudio/BrushStudioView.swift ColorTab` — Live Color -osio:
  - Lähteen valinta (Picker)
  - Väripikkerit A ja B
  - LinearGradient-preview A→B
  - Threshold ja Release speed sliderit
- `liveGradientColors()` helper-funktio BrushStudioViewin ulkopuolella

### Käyttö:
1. Avaa Brush Studio → valitse Tentacle-preset tai luo uusi
2. Color-välilehdellä → Live Color (Input) -osio
3. Valitse Source: esim. "Xbox Right Stick X" tai "Mic Pitch"
4. Säädä värit A (matala) ja B (korkea)
5. Säädä Threshold ja Release
6. Piirrä — väri muuttuu reaaliajassa stickiä/ääntä liikuttamalla


## v0.9 — Tentacle saumaton liukuväri (tämä sessio)

### Diagnoosi kuvasta:
- Vanha koodi teki per-3-pisteen segment -entiteettejä joista jokaisella oma tasainen väri
- Tulos: teräviä geometrisia rajoja kuin polygonipolygoni-faketteja
- Haluttu: auringonlaskun kaltainen jatkuva sulava liukuväri

### Ratkaisu:
- `makeTentacle()` kirjoitettu kokonaan uudelleen per-ring-arkkitehtuurilla
- Jokainen "rengas" (cross-section) on yksi entity
- Kaksi peräkkäistä rengasta muodostaa yhden thin-segment-entityn
- Segment-entityn väri = edellisen + nykyisen renkaan värin KESKIARVO
- → GPU:n Gouraud-shading interpoloi luontaisesti renkaan sisällä
- → Näkyvät rajat häviävät kun segmentit ovat 1-pisteen välein

### Värin laskenta per-rengas (ringColor()):
- Jos liveSource aktiivinen: interpoloi A→B lyhintä hue-reittiä, gradientValue = liveColorT
- Muuten: normaali pointColor() + ColorMode (gradient, rainbow, noise jne.)
- Pieni satunnainen hueShift ±0.05 lisää orgaanisuutta

### Miksi tämä toimii:
- Jokainen segment on 1 pisteen paksu → mitä tiheämmin piirretty, sitä hienompi väriresoluutio
- SimpleMaterial interpoloi värin per-face (ei per-vertex) — mutta kun facet on pieni, efekti on saumaton
- Väri laskee mid-color = (rengas[i] + rengas[i-1]) / 2 → vähentää hypähdyksiä
- LiveColorT tallennetaan gradientValue-kenttään per-pisteeseen → arvo säilyy kun stroke on valmis

