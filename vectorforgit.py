import os
import sys
import speech_recognition as sr
import subprocess
import requests
import psutil
import threading
from groq import Groq
from datetime import datetime
from PyQt6.QtWidgets import QApplication, QLabel, QWidget
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QPixmap

# --- CONFIGURATION ---
# Mütləq yeni gsk_ açarını bura qoy!
GROQ_API_KEY = "" 
CHESS_USERNAME = "azadlari"
MODEL_ID = "llama-3.3-70b-versatile"
client = Groq(api_key=GROQ_API_KEY)

# Spotify Bodybuilding Playlist ID (Sənin üçün standart ağır məşq siyahısı)
SPOTIFY_PLAYLIST_ID = ""

# CVUT Cədvəlin (PDF-dən gələn dəqiq dərslər)
STUDENT_SCHEDULE = {
    "Monday": [{"time": "09:15", "sub": "DBS", "room": "JPB-671"}, {"time": "12:45", "sub": "SAP", "room": "19:155"}],
    "Tuesday": [{"time": "09:15", "sub": "TUR", "room": "TH:A-1142"}, {"time": "14:30", "sub": "TUR", "room": "19:107"}],
    "Wednesday": [{"time": "08:15", "sub": "MA1", "room": "IP:8-571"}, {"time": "12:45", "sub": "PS1", "room": "IP:8-671"}],
    "Thursday": [{"time": "11:00", "sub": "SAP", "room": "TH:A-1042"}, {"time": "12:45", "sub": "MA1", "room": "19:301"}],
    "Friday": [{"time": "12:45", "sub": "PS1", "room": "19:344"}]
}

# --- HUD UI (PyQt6) ---
class VectorHUD(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.SubWindow)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.label = QLabel(self)
        if os.path.exists("hud.png"):
            pixmap = QPixmap("hud.png").scaled(400, 400, Qt.AspectRatioMode.KeepAspectRatio)
            self.label.setPixmap(pixmap)
        self.setGeometry(50, 50, 400, 400)
        self.hide()

    def show_hud(self, duration=6000):
        self.show()
        QTimer.singleShot(duration, self.hide)

# --- UTILITY FUNCTIONS ---
def speak(text):
    print(f"Vector: {text}")
    os.system(f'say -v Daniel -r 195 "{text}" &')

def get_vitals():
    return f"CPU: {psutil.cpu_percent()}%. RAM: {psutil.virtual_memory().percent}%. M4 performing optimally."

def get_next_class():
    now = datetime.now()
    day = now.strftime("%A")
    current_time = now.strftime("%H:%M")
    if day not in STUDENT_SCHEDULE: return "It's the weekend, Sir. Pursue Azadox."
    for l in STUDENT_SCHEDULE[day]:
        if l["time"] > current_time: return f"Next class: {l['sub']} at {l['time']} in {l['room']}."
    return "Classes completed for today. Time for gym?"

def play_workout_music():
    speak("Gym mode initiated. Remember the 70 kilogram goal. Let's grow, Mr. Azadlari.")
    os.system(f"open -a Spotify")
    os.system(f"osascript -e 'tell application \"Spotify\" to play track \"spotify:playlist:{SPOTIFY_PLAYLIST_ID}\"'")

def convert_bolt(cmd):
    try:
        amount = [int(s) for s in cmd.split() if s.isdigit()][0]
        # Təxmini kurs: 1 CZK = 0.073 AZN
        return f"Sir, {amount} Crowns is approximately {round(amount * 0.073, 2)} Manats."
    except: return "Please specify the crown amount."

def listen():
    r = sr.Recognizer()
    r.energy_threshold = 300 # Səs həssaslığı (aşağı = daha həssas)
    r.dynamic_energy_threshold = True
    with sr.Microphone() as source:
        print("... listening ...")
        r.adjust_for_ambient_noise(source, duration=0.6)
        try:
            audio = r.listen(source, timeout=10, phrase_time_limit=4)
            text = r.recognize_google(audio, language="en-US").lower()
            print(f"Heard: {text}") # Debug üçün nə eşitdiyini göstərir
            return text
        except: return ""

def vector_brain(cmd, hud_ui):
    if not cmd: return True
    hud_ui.show_hud(8000)
    
    # Komandalar
    if any(word in cmd for word in ["gym", "workout", "training"]): play_workout_music()
    elif "vital" in cmd or "system" in cmd: speak(get_vitals())
    elif "class" in cmd or "schedule" in cmd: speak(get_next_class())
    elif "convert" in cmd or "crown" in cmd: speak(convert_bolt(cmd))
    elif "screenshot" in cmd:
        subprocess.run(["screencapture", f"{os.path.expanduser('~')}/Desktop/SS_{datetime.now().strftime('%H%M%S')}.png"])
        speak("Visual captured.")
    elif "open" in cmd:
        app = cmd.replace("open", "").strip().capitalize()
        subprocess.run(["open", "-a", app]); speak(f"Launching {app}.")
    elif "stop" in cmd: speak("Standby mode."); return False
    else:
        try:
            res = client.chat.completions.create(
                messages=[{"role": "system", "content": "Minimalist AI. Max 15 words. Jarvis-like tone. Mention 70kg weight goal only if gym is mentioned."}, {"role": "user", "content": cmd}],
                model=MODEL_ID
            ).choices[0].message.content
            speak(res)
        except: speak("Uplink unstable, Sir.")
    return True

def main_loop(hud_ui):
    speak("System standby. Mainframe synchronized, Mr. Azadlari.")
    while True:
        text = listen()
        # Oyanma sözlərini genişləndirdik (Google bəzən "Victor" eşidir)
        if any(w in text for w in ["vector", "victor", "vəziyyət", "hey", "back", "vektor"]):
            hud_ui.show_hud(3000)
            speak("Online. Listening...")
            command = listen()
            if command:
                if not vector_brain(command, hud_ui): break
    os._exit(0)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    hud = VectorHUD()
    threading.Thread(target=main_loop, args=(hud,), daemon=True).start()
    sys.exit(app.exec())