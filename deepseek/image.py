
import tkinter as tk
from tkinter import filedialog, messagebox
import cv2
import pytesseract
from PIL import Image, ImageTk

class CodeDetectionWindow:
    def __init__(self, master):
        self.master = master
        master.title("Code Detection Window")
        master.geometry("800x600")

        self.canvas = tk.Canvas(master, width=700, height=400)
        self.canvas.pack(pady=10)

        self.select_button = tk.Button(master, text="Select Image", command=self.select_image)
        self.select_button.pack(pady=5)

        self.detect_button = tk.Button(master, text="Detect Code", command=self.detect_code)
        self.detect_button.pack(pady=5)

        self.result_text = tk.Text(master, height=10, width=80)
        self.result_text.pack(pady=10)

        self.image = None
        self.image_path = None

    def select_image(self):
        self.image_path = filedialog.askopenfilename(filetypes=[("Image files", "*.png *.jpg *.jpeg *.bmp")])
        if self.image_path:
            self.image = cv2.imread(self.image_path)
            self.display_image(self.image)

    def display_image(self, image):
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(image)
        image.thumbnail((700, 400))
        photo = ImageTk.PhotoImage(image)
        self.canvas.create_image(0, 0, anchor=tk.NW, image=photo)
        self.canvas.image = photo

    def detect_code(self):
        if self.image is None:
            messagebox.showerror("Error", "Please select an image first.")
            return

        gray = cv2.cvtColor(self.image, cv2.COLOR_BGR2GRAY)
        text = pytesseract.image_to_string(gray)

        # Simple heuristic to detect if the text looks like code
        code_keywords = ['def', 'class', 'import', 'for', 'while', 'if', 'else', 'return', 'print']
        if any(keyword in text for keyword in code_keywords):
            self.result_text.delete(1.0, tk.END)
            self.result_text.insert(tk.END, "Code detected:\n\n")
            self.result_text.insert(tk.END, text)
        else:
            self.result_text.delete(1.0, tk.END)
            self.result_text.insert(tk.END, "No code detected in the image.")

if __name__ == "__main__":
    root = tk.Tk()
    app = CodeDetectionWindow(root)
    root.mainloop()
