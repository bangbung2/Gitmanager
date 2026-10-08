#!/data/data/com.termux/files/usr/bin/bash

CONFIG_FILE="$HOME/.git_config_helper"
STORAGE_DIR="/sdcard/github_projects"
APK_OUTPUT_DIR="/sdcard/Download/Build_APK"

git config --global --add safe.directory "*" 2>/dev/null

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

mkdir -p "$STORAGE_DIR"
mkdir -p "$APK_OUTPUT_DIR"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    if [ -n "$GH_USER" ]; then
        git config --global user.name "$GH_USER" 2>/dev/null
        git config --global user.email "$GH_USER@users.noreply.github.com" 2>/dev/null
    fi
}

save_config() {
    echo "GH_USER=\"$GH_USER\"" > "$CONFIG_FILE"
    echo "GH_TOKEN=\"$GH_TOKEN\"" >> "$CONFIG_FILE"
    echo "DEFAULT_REPO=\"$DEFAULT_REPO\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    git config --global user.name "$GH_USER" 2>/dev/null
    git config --global user.email "$GH_USER@users.noreply.github.com" 2>/dev/null
}

setup_credentials() {
    echo -e "${CYAN}=== PENGATURAN KREDENSIAL GITHUB ===${NC}"
    read -rp "Masukkan Username GitHub: " input_user
    read -rp "Masukkan Personal Access Token (PAT): " input_token
    read -rp "Nama Repo Default (Opsional, tekan Enter jika kosong): " input_repo

    GH_USER="$input_user"
    GH_TOKEN="$input_token"
    DEFAULT_REPO="$input_repo"

    save_config
    echo -e "${GREEN}[✓] Data kredensial berhasil disimpan!${NC}\n"
}

check_credentials() {
    load_config
    if [ -z "$GH_USER" ] || [ -z "$GH_TOKEN" ]; then
        echo -e "${YELLOW}[!] Data login belum ada. Atur terlebih dahulu.${NC}"
        setup_credentials
    fi
}

select_project_dir() {
    mapfile -t FOLDERS < <(find "$STORAGE_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null)
    local count=${#FOLDERS[@]}

    echo -e "${CYAN}=== PILIH PROYEK / FOLDER REPO ===${NC}"
    if [ "$count" -gt 0 ]; then
        for i in "${!FOLDERS[@]}"; do
            echo -e "$((i+1)). ${GREEN}${FOLDERS[$i]}${NC}"
        done
        echo -e "$((count+1)). ${MAGENTA}[Ketik Nama Folder Manual Lainnya]${NC}"
    else
        echo -e "${YELLOW}[!] Belum ada folder proyek di $STORAGE_DIR${NC}"
        echo -e "1. ${MAGENTA}[Ketik Nama Folder / Repo Manual]${NC}"
    fi

    local prompt_default="1"
    read -rp "Pilih nomor [1]: " choice
    choice=${choice:-$prompt_default}

    if [ "$count" -gt 0 ] && [ "$choice" -le "$count" ] && [ "$choice" -ge 1 ]; then
        local idx=$((choice-1))
        SELECTED_FOLDER="${FOLDERS[$idx]}"
    else
        read -rp "Ketik nama folder proyek / repo: " manual_name
        SELECTED_FOLDER="$manual_name"
    fi

    if [ -z "$SELECTED_FOLDER" ]; then
        echo -e "${RED}[✗] Folder tidak boleh kosong! Membatalkan aksi.${NC}\n"
        return 1
    fi
    echo -e "${GREEN}[✓] Target proyek terpilih: ${CYAN}$SELECTED_FOLDER${NC}\n"
    return 0
}

fetch_and_select_branch() {
    local repo_target="$1"
    echo -e "${YELLOW}[*] Mengambil daftar branch dari GitHub untuk $repo_target...${NC}"
    
    BRANCH_LIST_RAW=$(curl -s -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$GH_USER/$repo_target/branches")

    mapfile -t BRANCHES < <(echo "$BRANCH_LIST_RAW" | jq -r '.[].name' 2>/dev/null)
    local count=${#BRANCHES[@]}

    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}[!] Tidak dapat membaca branch via API. Masukkan branch manual:${NC}"
        read -rp "Nama branch [main/master]: " manual_branch
        CHOSEN_BRANCH="${manual_branch:-main}"
        return
    fi

    echo -e "${MAGENTA}--- Pilih Branch Tujuan ---${NC}"
    for i in "${!BRANCHES[@]}"; do
        echo "$((i+1)). ${BRANCHES[$i]}"
    done
    read -rp "Pilih nomor branch [1]: " choice
    choice=${choice:-1}
    local idx=$((choice-1))
    CHOSEN_BRANCH="${BRANCHES[$idx]:-${BRANCHES[0]}}"
    echo -e "${GREEN}[✓] Branch terpilih: $CHOSEN_BRANCH${NC}"
}

create_and_push_new_repo() {
    check_credentials
    echo -e "${CYAN}=== JADIKAN FOLDER SEBAGAI REPO GITHUB BARU ===${NC}"
    echo "1. Pilih folder yang ada di $STORAGE_DIR"
    echo "2. Masukkan path folder bebas (contoh: /sdcard/Download/mod-clash)"
    read -rp "Pilihan lokasi folder [1]: " folder_source
    folder_source=${folder_source:-1}

    local target_path=""
    if [ "$folder_source" == "1" ]; then
        select_project_dir || return
        target_path="$STORAGE_DIR/$SELECTED_FOLDER"
    else
        read -rp "Ketik path lengkap folder: " input_custom_path
        if [ ! -d "$input_custom_path" ]; then
            echo -e "${RED}[✗] Folder tidak ditemukan di: $input_custom_path${NC}\n"
            return
        fi
        target_path="$input_custom_path"
    fi

    local default_name
    default_name=$(basename "$target_path")
    read -rp "Nama repositori di GitHub [$default_name]: " new_repo_name
    new_repo_name=${new_repo_name:-$default_name}

    read -rp "Jadikan repo Private? (y/n) [y]: " is_private
    is_private=${is_private:-y}
    local private_flag="true"
    if [[ "$is_private" =~ ^[Nn]$ ]]; then
        private_flag="false"
    fi

    echo -e "${YELLOW}[*] Membuat repo baru '$new_repo_name' di GitHub...${NC}"
    CREATE_RESP=$(curl -s -X POST \
      -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/user/repos \
      -d "{\"name\":\"$new_repo_name\", \"private\":$private_flag}")

    CLONE_URL=$(echo "$CREATE_RESP" | jq -r '.clone_url // empty')

    if [ -z "$CLONE_URL" ]; then
        ERR_MSG=$(echo "$CREATE_RESP" | jq -r '.message // "Gagal membuat repositori"')
        echo -e "${RED}[✗] API Error: $ERR_MSG${NC}"
        echo -e "${YELLOW}[!] Jika repo sudah ada di GitHub, proses push akan tetap dicoba.${NC}"
    else
        echo -e "${GREEN}[✓] Repo https://github.com/$GH_USER/$new_repo_name berhasil dibuat!${NC}"
    fi

    cd "$target_path" || return

    echo -e "${YELLOW}[*] Menyiapkan Git lokal di $target_path...${NC}"
    [ ! -d ".git" ] && git init
    git branch -M main

    grep -qxF "*.apk" .gitignore 2>/dev/null || echo -e "\n*.apk\n*.zip" >> .gitignore

    REMOTE_URL="https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$new_repo_name.git"
    git remote remove origin 2>/dev/null
    git remote add origin "$REMOTE_URL"

    echo -e "${YELLOW}[*] Menambahkan seluruh file dan subfolder...${NC}"
    git add -A

    read -rp "Pesan Commit [Initial Commit]: " custom_commit
    custom_commit=${custom_commit:-"Initial Commit via MT Manager - $(date '+%Y-%m-%d %H:%M:%S')"}

    git commit -m "$custom_commit"

    echo -e "${YELLOW}[*] Mengunggah (Push) seluruh file ke main...${NC}"
    if git push -u origin main; then
        echo -e "${GREEN}[✓] SUKSES! Satu folder berhasil jadi repo GitHub: ${CYAN}https://github.com/$GH_USER/$new_repo_name${NC}\n"
    else
        echo -e "${YELLOW}[!] Push standar gagal, mencoba opsi Force Push...${NC}"
        git push -u origin main --force
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[✓] BERHASIL ditimpa dengan Force Push!${NC}\n"
        else
            echo -e "${RED}[✗] Gagal push. Cek kembali izin PAT (Personal Access Token).${NC}\n"
        fi
    fi
}

clone_repository() {
    check_credentials
    echo -e "${CYAN}=== CLONE REPOSITORI ===${NC}"
    read -rp "Ketik nama repositori GitHub yang mau di-clone: " repo_name

    if [ -z "$repo_name" ]; then
        echo -e "${RED}[✗] Nama repo tidak boleh kosong!${NC}\n"
        return
    fi

    TARGET_DIR="$STORAGE_DIR/$repo_name"
    if [ -d "$TARGET_DIR" ]; then
        echo -e "${YELLOW}[!] Folder $TARGET_DIR sudah ada di memori internal!${NC}\n"
        return
    fi

    echo -e "${YELLOW}[*] Mengkloning https://github.com/$GH_USER/$repo_name ...${NC}"
    git clone "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$repo_name.git" "$TARGET_DIR"

    if [ $? -eq 0 ]; then
        cd "$TARGET_DIR" || exit
        git config user.name "$GH_USER"
        git config user.email "$GH_USER@users.noreply.github.com"
        grep -qxF "*.apk" .gitignore 2>/dev/null || echo -e "\n*.apk\n*.zip" >> .gitignore
        echo -e "${GREEN}[✓] Sukses clone ke: $TARGET_DIR${NC}\n"
    else
        echo -e "${RED}[✗] Gagal clone. Cek token atau nama repo.${NC}\n"
    fi
}

push_changes() {
    check_credentials
    select_project_dir || return
    TARGET_DIR="$STORAGE_DIR/$SELECTED_FOLDER"

    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${RED}[✗] Folder $TARGET_DIR tidak ditemukan di $STORAGE_DIR!${NC}\n"
        return
    fi

    cd "$TARGET_DIR" || return

    git config user.name "$GH_USER"
    git config user.email "$GH_USER@users.noreply.github.com"

    echo -e "${CYAN}[*] Folder target: $SELECTED_FOLDER${NC}"
    fetch_and_select_branch "$SELECTED_FOLDER"
    TARGET_BRANCH="$CHOSEN_BRANCH"

    git rm --cached *.apk 2>/dev/null
    git rm --cached *.zip 2>/dev/null

    CHANGES=$(git status --porcelain)
    UNPUSHED=$(git log "origin/$TARGET_BRANCH..HEAD" --oneline 2>/dev/null)

    if [ -z "$CHANGES" ] && [ -z "$UNPUSHED" ]; then
        echo -e "${YELLOW}[!] Tidak ada perubahan baru atau commit lokal yang tertinggal.${NC}\n"
        return
    fi

    if [ -n "$CHANGES" ]; then
        echo -e "${YELLOW}[*] Menyimpan file yang dimodifikasi...${NC}"
        git add -A
        git status -s
        COMMIT_MSG="Update via MT Manager - $(date '+%Y-%m-%d %H:%M:%S')"
        git commit -m "$COMMIT_MSG"
    else
        echo -e "${YELLOW}[*] Ditemukan commit lokal. Memproses push...${NC}"
    fi

    echo -e "${YELLOW}[*] Mengunggah (Push) ke branch '$TARGET_BRANCH'...${NC}"
    PUSH_OUTPUT=$(git push "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$SELECTED_FOLDER.git" "HEAD:$TARGET_BRANCH" 2>&1)
    PUSH_STATUS=$?

    if [ $PUSH_STATUS -eq 0 ]; then
        echo -e "${GREEN}[✓] BERHASIL! Perubahan berhasil terunggah ke branch '$TARGET_BRANCH'.${NC}\n"
    else
        echo -e "${RED}[✗] Push reguler ditolak: $PUSH_OUTPUT${NC}"
        echo -e "${YELLOW}[?] Apakah ingin menimpa (Force Push) ke branch '$TARGET_BRANCH'?${NC}"
        echo "1. Ya, Timpa langsung (Force Push)"
        echo "2. Batal"
        read -rp "Pilihan [1]: " force_choice
        force_choice=${force_choice:-1}
        if [ "$force_choice" == "1" ]; then
            echo -e "${YELLOW}[*] Melakukan Force Push...${NC}"
            git push "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$SELECTED_FOLDER.git" "HEAD:$TARGET_BRANCH" --force
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[✓] BERHASIL! Branch '$TARGET_BRANCH' berhasil ditimpa dengan kode lokal.${NC}\n"
            else
                echo -e "${RED}[✗] Gagal force push. Periksa token PAT.${NC}\n"
            fi
        else
            echo -e "${YELLOW}[i] Push dibatalkan.${NC}\n"
        fi
    fi
}

pull_updates() {
    check_credentials
    select_project_dir || return
    TARGET_DIR="$STORAGE_DIR/$SELECTED_FOLDER"

    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${RED}[✗] Folder tidak ditemukan!${NC}\n"
        return
    fi

    cd "$TARGET_DIR" || return
    fetch_and_select_branch "$SELECTED_FOLDER"
    git pull "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$SELECTED_FOLDER.git" "$CHOSEN_BRANCH"
    echo -e "${GREEN}[✓] Data lokal berhasil disinkronkan dengan branch $CHOSEN_BRANCH.${NC}\n"
}

check_build_error() {
    check_credentials
    select_project_dir || return
    local repo_name="$SELECTED_FOLDER"

    echo -e "${YELLOW}[*] Mengambil riwayat build terakhir untuk $repo_name...${NC}"
    
    RUN_DATA=$(curl -s -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$GH_USER/$repo_name/actions/runs?status=completed&per_page=1")

    RUN_ID=$(echo "$RUN_DATA" | jq -r '.workflow_runs[0].id // empty')
    CONCLUSION=$(echo "$RUN_DATA" | jq -r '.workflow_runs[0].conclusion // empty')
    RUN_NAME=$(echo "$RUN_DATA" | jq -r '.workflow_runs[0].name // empty')

    if [ -z "$RUN_ID" ]; then
        RUN_DATA=$(curl -s -H "Authorization: token $GH_TOKEN" \
          "https://api.github.com/repos/$GH_USER/$repo_name/actions/runs?per_page=1")
        RUN_ID=$(echo "$RUN_DATA" | jq -r '.workflow_runs[0].id // empty')
        CONCLUSION=$(echo "$RUN_DATA" | jq -r '.workflow_runs[0].conclusion // empty')
        RUN_NAME=$(echo "$RUN_DATA" | jq -r '.workflow_runs[0].name // empty')
    fi

    if [ -z "$RUN_ID" ]; then
        echo -e "${RED}[✗] Tidak ada riwayat build yang ditemukan!${NC}\n"
        return
    fi

    local status_color="${RED}"
    [ "$CONCLUSION" == "success" ] && status_color="${GREEN}"
    [ -z "$CONCLUSION" ] && CONCLUSION="in_progress"

    echo -e "Workflow: ${CYAN}$RUN_NAME${NC} | Run ID: ${YELLOW}$RUN_ID${NC} | Status: ${status_color}$CONCLUSION${NC}"

    if [ "$CONCLUSION" == "success" ]; then
        echo -e "${GREEN}[✓] Build terakhir ini sukses (SUCCESS), tidak ada error!${NC}\n"
        return
    fi

    if [ "$CONCLUSION" == "in_progress" ]; then
        echo -e "${YELLOW}[!] Build saat ini masih berjalan (in_progress). Harap tunggu selesai agar log tersedia.${NC}\n"
        return
    fi

    TEMP_DIR="$HOME/.build_error_check"
    LOG_SAVED_DIR="$HOME/build_error_logs"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    mkdir -p "$LOG_SAVED_DIR"

    echo -e "${YELLOW}[*] Mengunduh arsip log GitHub Actions...${NC}"
    curl -s -L -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$GH_USER/$repo_name/actions/runs/$RUN_ID/logs" -o "$TEMP_DIR/logs.zip"

    if [ ! -s "$TEMP_DIR/logs.zip" ]; then
        echo -e "${RED}[✗] File log kosong atau token PAT tidak memiliki izin actions read.${NC}\n"
        rm -rf "$TEMP_DIR"
        return
    fi

    unzip -q "$TEMP_DIR/logs.zip" -d "$TEMP_DIR/extracted" 2>/dev/null
    cp -r "$TEMP_DIR/extracted/"* "$LOG_SAVED_DIR/" 2>/dev/null

    echo -e "\n${RED}================ HASIL ANALISIS ERROR (LENGKAP) ================${NC}"

    mapfile -t ALL_LOGS < <(find "$TEMP_DIR/extracted" -type f -name "*.txt" 2>/dev/null)

    if [ ${#ALL_LOGS[@]} -eq 0 ]; then
        echo -e "${RED}[✗] Tidak ada file teks log yang berhasil diekstrak.${NC}"
        echo -e "${RED}================================================================${NC}\n"
        rm -rf "$TEMP_DIR"
        return
    fi

    FOUND_ERROR=0

    for log_file in "${ALL_LOGS[@]}"; do
        if grep -q "Task :.* FAILED" "$log_file" 2>/dev/null; then
            local fname
            fname=$(basename "$log_file")
            echo -e "${YELLOW}[!] Kegagalan Task Gradle pada file log: ${CYAN}$fname${NC}"
            echo -e "${BLUE}----------------------------------------------------------------${NC}"
            
            grep -B 35 -A 5 "Task :.* FAILED" "$log_file" | sed 's/^[0-9T:.Z-]* //' | while read -r line; do
                if echo "$line" | grep -qiE "(FAILED|error:|AAPT:|FAILURE|\* What went wrong|Caused by:)"; then
                    echo -e "${RED}$line${NC}"
                else
                    echo -e "${CYAN}$line${NC}"
                fi
            done
            
            FOUND_ERROR=1
            echo -e "${BLUE}----------------------------------------------------------------${NC}\n"
        fi
    done

    if [ $FOUND_ERROR -eq 0 ]; then
        for log_file in "${ALL_LOGS[@]}"; do
            if grep -qiE "(\* What went wrong:|Execution failed for task)" "$log_file" 2>/dev/null; then
                local fname
                fname=$(basename "$log_file")
                echo -e "${YELLOW}[!] Rincian kegagalan build pada file log: ${CYAN}$fname${NC}"
                echo -e "${BLUE}----------------------------------------------------------------${NC}"
                grep -B 10 -A 25 -iE "(\* What went wrong:|Execution failed for task)" "$log_file" | sed 's/^[0-9T:.Z-]* //' | while read -r line; do
                    if echo "$line" | grep -qiE "(FAILED|error|FAILURE|What went wrong|Caused by)"; then
                        echo -e "${RED}$line${NC}"
                    else
                        echo -e "${CYAN}$line${NC}"
                    fi
                done
                FOUND_ERROR=1
                echo -e "${BLUE}----------------------------------------------------------------${NC}\n"
                break
            fi
        done
    fi

    if [ $FOUND_ERROR -eq 0 ]; then
        BIGGEST_LOG=$(find "$TEMP_DIR/extracted" -type f -name "*.txt" -exec ls -S {} + 2>/dev/null | head -n 1)
        if [ -n "$BIGGEST_LOG" ] && [ -f "$BIGGEST_LOG" ]; then
            echo -e "${YELLOW}[*] Menampilkan 50 baris akhir dari log utama ($(basename "$BIGGEST_LOG")):${NC}"
            tail -n 50 "$BIGGEST_LOG" | sed 's/^[0-9T:.Z-]* //' | while read -r line; do
                echo -e "${RED}$line${NC}"
            done
        fi
    fi

    echo -e "${GREEN}[i] Arsip log lengkap tersimpan di: ${CYAN}$LOG_SAVED_DIR/${NC}"
    echo -e "${RED}================================================================${NC}\n"
    rm -rf "$TEMP_DIR"
}

download_latest_artifact() {
    local repo_name="$1"
    local run_id="$2"

    if [ -z "$run_id" ]; then
        echo -e "${YELLOW}[*] Mencari riwayat build terakhir di $repo_name...${NC}"
        run_id=$(curl -s -H "Authorization: token $GH_TOKEN" \
          "https://api.github.com/repos/$GH_USER/$repo_name/actions/runs?status=completed&conclusion=success&per_page=1" | jq -r '.workflow_runs[0].id // empty')
    fi

    if [ -z "$run_id" ]; then
        echo -e "${RED}[✗] Tidak ada riwayat build sukses yang ditemukan.${NC}\n"
        return 1
    fi

    ARTIFACTS_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$GH_USER/$repo_name/actions/runs/$run_id/artifacts")

    ARTIFACT_ID=$(echo "$ARTIFACTS_JSON" | jq -r '.artifacts[0].id // empty')

    if [ -z "$ARTIFACT_ID" ]; then
        echo -e "${RED}[✗] Artifact APK tidak ditemukan pada Run ID: $run_id.${NC}\n"
        return 1
    fi

    echo -e "${YELLOW}[*] Mengambil link CDN unduhan GitHub...${NC}"
    DIRECT_URL=$(curl -s -I -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$GH_USER/$repo_name/actions/artifacts/$ARTIFACT_ID/zip" | \
      grep -i "^location:" | awk '{print $2}' | tr -d '\r')

    ZIP_TARGET="$APK_OUTPUT_DIR/app-release.zip"
    rm -f "$ZIP_TARGET"

    echo -e "${GREEN}[*] Mengunduh APK (Maksimal 16-Thread Stabil)...${NC}"
    ARIA_FLAGS="-x 16 -s 16 -j 16 -k 1M --file-allocation=none --console-log-level=warn --download-result=hide --summary-interval=1"

    if [ -n "$DIRECT_URL" ]; then
        aria2c $ARIA_FLAGS -d "$APK_OUTPUT_DIR" -o "app-release.zip" "$DIRECT_URL"
    else
        aria2c $ARIA_FLAGS --header="Authorization: token $GH_TOKEN" \
          -d "$APK_OUTPUT_DIR" -o "app-release.zip" \
          "https://api.github.com/repos/$GH_USER/$repo_name/actions/artifacts/$ARTIFACT_ID/zip"
    fi

    printf "\r\033[K"

    if [ -f "$ZIP_TARGET" ]; then
        echo -e "${YELLOW}[*] Mengekstrak file APK...${NC}"
        unzip -o "$ZIP_TARGET" -d "$APK_OUTPUT_DIR/" >/dev/null 2>&1
        rm -f "$ZIP_TARGET"
        echo -e "${GREEN}[✓] SELESAI! APK berhasil disimpan di: ${CYAN}$APK_OUTPUT_DIR/${NC}"
        echo -e "${CYAN}[i] Buka MT Manager: Internal Storage > Download > Build_APK${NC}\n"
        return 0
    else
        echo -e "${RED}[✗] Unduhan gagal diselesaikan.${NC}\n"
        return 1
    fi
}

download_only_apk() {
    check_credentials
    select_project_dir || return
    download_latest_artifact "$SELECTED_FOLDER" ""
}

build_and_download_apk() {
    check_credentials
    select_project_dir || return
    local repo_name="$SELECTED_FOLDER"
    TARGET_DIR="$STORAGE_DIR/$repo_name"
    
    mkdir -p "$APK_OUTPUT_DIR"

    fetch_and_select_branch "$repo_name"
    local target_branch="$CHOSEN_BRANCH"

    echo -e "${YELLOW}[*] Mengambil konfigurasi workflow untuk $repo_name...${NC}"
    WORKFLOWS_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$GH_USER/$repo_name/actions/workflows")

    WORKFLOW_ID=$(echo "$WORKFLOWS_JSON" | jq -r '.workflows[0].id // empty')

    if [ -z "$WORKFLOW_ID" ]; then
        echo -e "${RED}[✗] File workflow yaml tidak ditemukan di repo $repo_name!${NC}\n"
        return
    fi

    echo -e "${YELLOW}[*] Menjalankan build Actions pada branch: $target_branch ...${NC}"
    curl -s -X POST \
      -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$GH_USER/$repo_name/actions/workflows/$WORKFLOW_ID/dispatches" \
      -d "{\"ref\":\"$target_branch\"}"

    echo -e "${GREEN}[✓] Perintah build berhasil dikirim ke branch $target_branch!${NC}"
    echo -e "${YELLOW}[*] Menunggu antrean runner GitHub...${NC}"
    sleep 8

    LATEST_RUN_ID=$(curl -s -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$GH_USER/$repo_name/actions/runs?per_page=1" | jq -r '.workflow_runs[0].id')

    echo -e "${CYAN}[*] Monitoring Run ID: $LATEST_RUN_ID${NC}"
    echo -e "${BLUE}------------------------------------------------------${NC}"

    while true; do
        JOBS_DATA=$(curl -s -H "Authorization: token $GH_TOKEN" \
          "https://api.github.com/repos/$GH_USER/$repo_name/actions/runs/$LATEST_RUN_ID/jobs")
        
        OVERALL_STATUS=$(echo "$JOBS_DATA" | jq -r '.jobs[0].status // "queued"')
        OVERALL_CONCLUSION=$(echo "$JOBS_DATA" | jq -r '.jobs[0].conclusion // empty')
        
        CURRENT_STEP=$(echo "$JOBS_DATA" | jq -r '.jobs[0].steps[] | select(.status=="in_progress") | .name' 2>/dev/null | tail -n 1)
        
        if [ -z "$CURRENT_STEP" ]; then
            CURRENT_STEP=$(echo "$JOBS_DATA" | jq -r '.jobs[0].steps[] | select(.conclusion=="success") | .name' 2>/dev/null | tail -n 1)
            [ -z "$CURRENT_STEP" ] && CURRENT_STEP="Menyiapkan runner environment..."
        fi

        if [ "$OVERALL_STATUS" == "completed" ]; then
            if [ "$OVERALL_CONCLUSION" == "success" ]; then
                echo -e "\n${GREEN}[✓] Build SUKSES! Memulai unduhan...${NC}"
                download_latest_artifact "$repo_name" "$LATEST_RUN_ID"
                break
            else
                echo -e "\n${RED}[✗] Build GAGAL pada step: $CURRENT_STEP${NC}"
                echo -e "${YELLOW}[i] Pilih Menu 7 untuk melihat detail error.${NC}\n"
                return
            fi
        else
            echo -e "Status: ${YELLOW}$OVERALL_STATUS${NC} | Step Aktif: ${CYAN}$CURRENT_STEP${NC}"
        fi

        sleep 12
    done
}

while true; do
    load_config
    echo -e "${CYAN}=====================================${NC}"
    echo -e "${GREEN}      GIT MANAGER FOR MT MANAGER     ${NC}"
    echo -e "${CYAN}=====================================${NC}"
    echo "User aktif   : ${GH_USER:-Belum diset}"
    echo "Lokasi Folder: $STORAGE_DIR"
    echo "Lokasi APK   : $APK_OUTPUT_DIR"
    echo "-------------------------------------"
    echo "1. Clone Repo ke Memori Internal"
    echo "2. Buat Repo Baru dari Folder & Push (Inisialisasi)"
    echo "3. Upload & Push Update ke GitHub (Repo yang Sudah Ada)"
    echo "4. Tarik Pembaruan dari GitHub (Pull)"
    echo "5. Build APK & Auto Download (Clean 16-Thread)"
    echo "6. Unduh APK Build Terakhir (Tanpa Build Ulang)"
    echo "7. Cek Detail Error Build (Auto Analisis)"
    echo "8. Atur Ulang Akun & Token PAT"
    echo "9. Keluar"
    echo "-------------------------------------"
    read -rp "Pilih menu [1-9]: " menu

    case $menu in
        1) clone_repository ;;
        2) create_and_push_new_repo ;;
        3) push_changes ;;
        4) pull_updates ;;
        5) build_and_download_apk ;;
        6) download_only_apk ;;
        7) check_build_error ;;
        8) setup_credentials ;;
        9) echo "Sampai jumpa!"; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}\n" ;;
    esac
done
