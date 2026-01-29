#!/bin/bash

cd /home/andres/Downloads

# Create directories
mkdir -p Documents/PDFs Documents/DOCs Images Archives Software Logs Scripts Media Code Others

# Move PDFs
find . -maxdepth 1 -type f -iname "*.pdf" -exec mv {} Documents/PDFs/ \;

# DOCs and presentations
find . -maxdepth 1 -type f \( -iname "*.doc" -o -iname "*.docx" -o -iname "*.pptx" \) -exec mv {} Documents/DOCs/ \;

# Images
find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.svg" -o -iname "*.avif" -o -iname "*.webp" \) -exec mv {} Images/ \;

# Archives
find . -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.7z" \) -exec mv {} Archives/ \;

# Software
find . -maxdepth 1 -type f \( -iname "*.deb" -o -iname "*.bin" -o -iname "*.exe" -o -iname "*.dmg" -o -iname "*.msi" \) -exec mv {} Software/ \;

# Logs
find . -maxdepth 1 -type f \( -iname "*log*" -o -iname "*.tgz" \) -exec mv {} Logs/ \;

# Scripts and text
find . -maxdepth 1 -type f \( -iname "*.sh" -o -iname "*.py" -o -iname "*.js" -o -iname "*.sql" -o -iname "*.md" -o -iname "*.txt" -o -iname "*.csv" -o -iname "*.json" -o -iname "*.xml" -o -iname "*.yaml" \) -exec mv {} Scripts/ \;

# Media
find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.m4a" -o -iname "*.mp3" \) -exec mv {} Media/ \;

# Code and notebooks
find . -maxdepth 1 -type f \( -iname "*.ipynb" -o -iname "*.tex" -o -iname "*.php" -o -iname "*.cs" -o -iname "*.mermaid" \) -exec mv {} Code/ \;

# Move remaining files and directories to Others
find . -maxdepth 1 \( -type f -o -type d \) ! -name . ! -name Documents ! -name Images ! -name Archives ! -name Software ! -name Logs ! -name Scripts ! -name Media ! -name Code ! -name Others -exec mv {} Others/ \;