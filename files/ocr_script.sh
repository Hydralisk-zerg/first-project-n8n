#!/bin/bash

# Простой OCR скрипт для PDF
INPUT_FILE="$1"
OUTPUT_DIR="/files/ocr_output"
FILENAME=$(basename "$INPUT_FILE" .pdf)

# Создаем директорию для вывода
mkdir -p "$OUTPUT_DIR"

# Используем ocrmypdf для OCR
ocrmypdf --language rus+eng --output-type txt "$INPUT_FILE" "$OUTPUT_DIR/${FILENAME}_ocr.txt"

# Выводим результат
if [ -f "$OUTPUT_DIR/${FILENAME}_ocr.txt" ]; then
    echo "OCR completed successfully"
    cat "$OUTPUT_DIR/${FILENAME}_ocr.txt"
else
    echo "OCR failed"
fi