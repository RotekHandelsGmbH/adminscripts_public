# Mehr Durchblick im Platten-Dschungel: Das „Disk-to-Controller Tree Visualizer“-Tool

## Wenn die Storage-Wartung zur Hölle wird...

Wer regelmäßig mit Servern arbeitet, die eine Vielzahl an Festplatten und unterschiedlichen Storage-Controllern nutzen, kennt das Problem: Im Fehlerfall wird es schnell unübersichtlich. Plattenausfälle, Temperaturprobleme, Firmwareversionen oder defekte Controller – und das alles quer verteilt über SATA, SAS und NVMe.

Was bleibt? Manuell Informationen über Tools wie `lspci`, `lsblk`, `smartctl`, `nvme` und Co. zusammensuchen – mühsam, fehleranfällig und vor allem: zeitraubend.

Doch es geht auch anders.

---

## 🧹 Die Lösung: Visualisierung statt Verwirrung

Das Open-Source-Projekt **Disk-to-Controller Tree Visualizer** (Autor: *bitranox*) bringt endlich Ordnung ins Chaos. Es handelt sich um ein Python-Skript, das alle im System vorhandenen Festplatten automatisch erkennt und sie übersichtlich nach ihrem zugehörigen Storage-Controller gruppiert. Egal ob SATA, SAS oder NVMe – alle Informationen landen in einer kompakten Baumansicht.

Das Tool zeigt unter anderem:

* ✅ SMART-Status
* 🌡️ Temperatur
* 📆 Modell & Kapazität
* 🧲 Schnittstelle & Link-Speed
* 🔣 Seriennummer
* 🔧 Firmware-Version

---

## 💡 Warum das wichtig ist

Gerade im Fehlerfall – wenn z.B. RAID-Volumes zusammenbrechen oder SMART-Fehler drohen – will man so schnell wie möglich wissen:

* *Welche Platte ist betroffen?*
* *Wo hängt sie (physisch und logisch)?*
* *Wie ist der Gesundheitszustand der anderen Laufwerke im selben Controller?*
* *Laufen alle Platten mit der erwarteten Link-Speed (z.B. SATA6 statt SATA3)?*
* *auf welchem HBA kann ich vielleicht noch eine Platte dazuquetschen ?*
* *welche NVMEs benötigen ein Firmwareupdate ?*

Genau hier spielt das Skript seine Stärke aus: Statt Dutzende Tools aufzurufen und Informationen manuell zu korrelieren, bekommt man sofort eine farblich strukturierte, logisch gruppierte Übersicht – direkt im Terminal.

---

## 📸 Beispielausgabe (gekürzt)

```bash
🎯 00:1f.2 Intel SATA AHCI Controller
  └── 📢 /dev/sda  (Hitachi HDS72202, 1.8T, SATA3, 🧹 link=SATA3, ❤️ SMART: ✅ , 🌡️ 42°C, 🔣 SN: JK11..., 🔧 FW: JKAOA3MA)
  └── 📢 /dev/sdb  (Hitachi HDS72302, 1.8T, SATA6, 🧹 link=SATA6, ❤️ SMART: ✅ , 🌡️ 39°C, ...)
🎯 03:00.0 Samsung NVMe Controller
  └── 📢 /dev/nvme0n1  Samsung 980 PRO, 2TB, NVMe, 🧹 link=PCIe 16.0 GT/s x4, ❤️ SMART: ✅ , 🌡️ 41°C, ...
```

---

## ⚙️ So funktioniert’s

Das Skript nutzt systemnahe Werkzeuge (`smartctl`, `nvme`, `lsblk`, `lspci`) und parst deren Ausgaben, um relevante Informationen zu extrahieren und übersichtlich darzustellen. Liegt die Linkgeschwindigkeit unter den Möglichkeiten des Drives, so wird dies z.B. rot hervorgehoben – ein häufig übersehenes Performanceproblemchen.

**Ausführung:**

```bash
sudo ./disk_controller_tree.py
# oder
sudo python3 ./disk_controller_tree.py
```

> **Hinweis**: die Root-Rechte sind notwendig, um SMART- und Controller-Daten vollständig auszulesen.

---

## 📦 Abhängigkeiten

Das Skript prüft beim Start automatisch, ob die folgenden Tools installiert sind und installiert diese im Hintergrund, sollte etwas fehlen:

* `smartmontools`
* `nvme-cli`
* `lspci`
* `lsblk`

---

## 👤 Fazit

Das „Disk-to-Controller Tree Visualizer“-Skript ist ein Segen für alle, die mit komplexer oder gewachsener Storage-Hardware arbeiten – sei es im Rechenzentrum, im NAS oder im Workstation-Bereich. Statt sich durch unzählige Low-Level-Tools zu hangeln, bekommt man eine übersichtliche, detailreiche und sofort verwertbare Zusammenfassung.

### 🔧 Ideal für:

* Server mit vielen Disks und Controllern
* Fehlersuche bei SMART-Warnungen
* Performanceanalyse (z.B. Link-Speed-Fehler)
* Hardware-Dokumentation & Audits

---

## 📅 Download & Mitmachen

Das Projekt ist quelloffen unter der **MIT-Lizenz** veröffentlicht. Du findest es z.B. auf GitHub unter dem Profil von **bitranox**.
