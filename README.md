# Docker Compose 教學：Flask + MySQL 8 + MySQL 9

本專案是一個循序漸進的教學範例，帶你完成三件事：

1. 沿用先前的經驗，用 **Dockerfile** 把 Flask 應用打包成 image
2. 建立 **Flask + MySQL 8 + MySQL 9** 三個容器
3. 用 **Docker Compose** 一個指令把三個服務串起來

## 學習目標

完成後你會理解：

- Dockerfile 每一行的用途，以及 image 與 container 的差別
- Compose 如何用「服務名稱」讓容器彼此連線（不需要 IP）
- 環境變數、port mapping、volume 各自解決什麼問題
- 為什麼同一台機器可以同時跑兩個版本的 MySQL

## 專案結構

```
docker_compose/
├── app/
│   ├── app.py              # Flask 程式（讀取 MySQL 的 Product 資料表）
│   └── requirements.txt    # Python 相依套件
├── Dockerfile              # 建立 Flask image 的設計圖
├── compose.yaml            # 三個服務的編排設定（變數由 .env 提供）
├── .env.example            # 環境變數範本（會進版控）
├── .env                    # 實際的帳號密碼（不進版控，需自行建立）
├── compose_script.sql      # 建立資料表與練習 SQL 的腳本
├── .dockerignore           # build image 時要排除的檔案
└── .gitignore              # git 要忽略的檔案
```

## 前置需求

- 已安裝 [Docker Desktop](https://www.docker.com/products/docker-desktop/)（內含 Docker Compose v2）
- 確認版本：

  ```bash
  docker --version
  docker compose version
  ```

---

## Step 1：理解 Flask 應用（`app/app.py`）

這支程式只做一件事：連到資料庫，查 `Product` 資料表，以 JSON 回傳。

重點有三個：

| 重點                 | 說明                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------------- |
| 連線資訊來自環境變數 | `DB_HOST`、`DB_NAME`、`DB_USER`、`DB_PASSWORD` 不寫死在程式裡，由 Compose 注入           |
| 連線失敗會重試       | `get_db_connection()` 每 2 秒重試一次，因為 MySQL 啟動需要時間，Flask 可能比資料庫先起來 |
| 監聽 `0.0.0.0:5001`  | 容器內必須監聽 `0.0.0.0`，外部才連得進來；只用 `127.0.0.1` 會連不到                      |

`requirements.txt` 內有 `cryptography`，這是 MySQL 8 以後預設的認證方式 `caching_sha2_password` 需要的套件，少了它連線會失敗。

## Step 2：用 Dockerfile 建立 Flask image

```dockerfile
FROM python:3.11-slim            # 基底 image：精簡版 Python
WORKDIR /app                     # 之後的指令都在 /app 底下執行
COPY app/requirements.txt .      # 先只複製相依清單
RUN pip install -r requirements.txt
RUN apt-get update && apt-get install -y nano
EXPOSE 5001                      # 宣告服務使用 5001（僅是文件性質）
COPY app/ .                      # 再複製程式碼
CMD ["python", "app.py"]         # 容器啟動時執行的指令
```

**為什麼先複製 `requirements.txt`、再複製程式碼？**
Docker 會逐層快取。只改 `app.py` 時，`pip install` 那層仍可使用快取，不用重新下載套件，build 會快很多。

### 單獨 build 並執行（可跳過，用來理解原理）

```bash
docker build -t yiwee-flask:local .
docker run --rm -p 5001:5001 yiwee-flask:local
```

此時 Flask 找不到資料庫（沒有設定 `DB_*` 環境變數），這是預期的。這正是下一步需要 Compose 的原因：**一個容器不夠，需要把應用與資料庫一起管理。**

## Step 3：認識 MySQL 容器

MySQL 官方 image 會讀取環境變數來初始化資料庫：

| 變數                            | 作用                   |
| ------------------------------- | ---------------------- |
| `MYSQL_ROOT_PASSWORD`           | root 密碼（必填）      |
| `MYSQL_DATABASE`                | 啟動時自動建立的資料庫 |
| `MYSQL_USER` / `MYSQL_PASSWORD` | 自動建立的一般使用者   |

資料存在容器內的 `/var/lib/mysql`，如果不掛 volume，容器刪除資料就消失。所以我們使用 **named volume** 保存。

## Step 4：用 `compose.yaml` 串起三個服務

### 服務一覽

| 服務     | Image                      | 對外 port（主機） | 說明                             |
| -------- | -------------------------- | ----------------- | -------------------------------- |
| `app`    | `yiweeeee/yiwee-flask:1.2` | 5001              | Flask 應用                       |
| `mysql8` | `mysql:8.0`                | 3306              | Flask 實際連線的資料庫           |
| `mysql9` | `mysql:9.0`                | 3307              | 獨立的 MySQL 9，用來對照版本差異 |

### 關鍵概念

**1. 服務名稱就是主機名稱**

```yaml
environment:
  DB_HOST: mysql8 # 不是 IP，是 compose.yaml 裡的服務名稱
```

Compose 會建立一個內部網路，容器之間可以直接用服務名稱互相連線。

**2. Port mapping：`主機 port:容器 port`**

```yaml
ports:
  - "3306:3306" # mysql8
  - "3307:3306" # mysql9：容器內仍是 3306，但主機改用 3307 避免衝突
```

兩個 MySQL 容器內部都使用 3306，彼此不會衝突；但對外要映射到主機的不同 port。

**3. Volume 保存資料**

```yaml
volumes:
  - mysql8-data:/var/lib/mysql # named volume，容器刪除後資料仍在
  - ./app:/app # bind mount，主機改程式碼，容器立即看到
```

**4. `depends_on` 只控制啟動順序**

它不會等 MySQL「準備好」才啟動 Flask，所以 `app.py` 才需要自己寫重試迴圈。

**5. `restart: unless-stopped`**

容器異常結束或 Docker 重啟時會自動拉起，除非你手動 stop。

### 關於 image 來源

`app` 服務使用的是已推到 Docker Hub 的 `yiweeeee/yiwee-flask:1.2`，它是 **multi-arch image**（同時包含 `linux/amd64` 與 `linux/arm64`），所以 Windows / Intel Mac / Apple Silicon Mac 都能直接 `docker compose up -d`，不需要額外設定。

如果只是想暫時用自己 build 的版本，把 `image:` 那行改成：

```yaml
build: .
```

### 如果 Docker Hub 上的 image 出問題：重新 build 並推送

下列情況代表 Docker Hub 上的 `yiweeeee/yiwee-flask:1.2` 需要重做：

| 症狀                                                                                   | 原因                                                              |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `no matching manifest for linux/arm64/v8`（或 `linux/amd64`）                          | image 沒有包含你這台機器的 CPU 架構                               |
| `app` 容器一直 `Restarting`，log 出現 `ModuleNotFoundError: No module named 'pymysql'` | image 是用別的專案 build 的，缺少本專案 `requirements.txt` 的套件 |
| `pull access denied` / `not found`                                                     | tag 不存在，或 repo 被刪除、改為私有                              |

**請務必在「本專案目錄」（也就是有這份 `Dockerfile` 與 `app/requirements.txt` 的目錄）重新 build。** 不要拿其他專案的 Dockerfile 來推，否則依賴會不一樣（例如缺少 `pymysql`、`cryptography`）。

```bash
# 1. 進入本專案目錄，確認 requirements.txt 內有 flask、pymysql、cryptography
cd docker_compose
cat app/requirements.txt

# 2. 登入 Docker Hub（只需做一次）
docker login

# 3. 建置 multi-arch image 並直接推送（<dockerhub-username> 換成你的帳號）
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <dockerhub-username>/yiwee-flask:1.2 \
  --push .

# 4. 確認遠端同時有兩種架構
docker buildx imagetools inspect <dockerhub-username>/yiwee-flask:1.2
```

注意事項：

- **不要用一般的 `docker build` + `docker push`。** 在 Apple Silicon 上這只會產生 arm64 image，Windows（amd64）會拉不到；反過來也一樣。一定要用 `buildx --platform linux/amd64,linux/arm64`。
- **相同 tag 會被覆蓋。** 覆蓋 `1.2` 會影響所有使用這個 tag 的人；想保留舊版可改推新 tag（如 `1.3`）。
- 換了帳號或 tag，記得同步修改 `compose.yaml` 的 `image:`。
- 推送完成後驗證：`docker compose pull app && docker compose up -d`。
- 只有修改 `requirements.txt` 或 `Dockerfile` 才需要重新 build；修改 `app.py` 不需要，因為 `./app:/app` 的 bind mount 會直接用本機檔案。

## Step 5：設定環境變數並啟動

帳號密碼不寫在 `compose.yaml`，而是放在 `.env`，Compose 會自動讀取。先從範本複製一份，並依需要修改：

```bash
cp .env.example .env
```

| 變數                      | 用途                     |
| ------------------------- | ------------------------ |
| `DB_NAME`                 | 資料庫名稱               |
| `DB_USER` / `DB_PASSWORD` | 應用程式使用的帳號與密碼 |
| `MYSQL_ROOT_PASSWORD`     | MySQL root 密碼          |

`compose.yaml` 以 `${DB_PASSWORD}` 的語法引用它們；必填變數若沒設定，會直接報錯並提示缺哪一個，不會用空密碼啟動。

啟動：

```bash
docker compose up -d
```

查看狀態與 log：

```bash
docker compose ps
docker compose logs -f app
```

第一次啟動 MySQL 需要約 10–30 秒初始化。這段期間 `app` 的 log 會出現「資料庫連線中...」，屬於正常現象。

## Step 6：建立資料表並匯入資料

資料表**不會自動建立**，需要手動執行 `compose_script.sql`：

```bash
docker compose exec -T mysql8 sh -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD"' < compose_script.sql
```

> ⚠️ 該腳本最後有 `UPDATE` 與 `DELETE` 練習：執行完後 `USB-C Cable` 會被刪除、耳機價格變成 1190。這是刻意設計的 SQL 練習。若想要乾淨的三筆資料，請只執行腳本中 `CREATE TABLE` 與 `INSERT` 的部分。
>
> 另外，`CREATE TABLE` 不是 `IF NOT EXISTS`，重複執行會報「table already exists」。

## Step 7：驗證

**瀏覽器或 curl 開啟 Flask：**

```bash
curl http://localhost:5001/
```

預期回傳：

```json
{
  "status": "success",
  "product_count": 2,
  "products": [ ... ]
}
```

**進入 MySQL 查看：**

```bash
# MySQL 8
docker compose exec mysql8 sh -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT * FROM Product;"'

# MySQL 9（獨立資料庫，一開始是空的）
docker compose exec mysql9 sh -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SHOW TABLES;"'
```

**用主機上的 MySQL client 連線：**

```bash
mysql -h127.0.0.1 -P3306 -u<DB_USER> -p testdb   # MySQL 8（密碼會提示輸入）
mysql -h127.0.0.1 -P3307 -u<DB_USER> -p testdb   # MySQL 9
```

## Step 8：進階練習

1. **讓 Flask 改連 MySQL 9**：把 `DB_HOST` 改為 `mysql9`，並對 mysql9 執行 `compose_script.sql`，再 `docker compose up -d` 觀察結果
2. **觀察兩版差異**：在兩個容器各執行 `SELECT VERSION();`
3. **驗證 volume**：執行 `docker compose down` 再 `up -d`，確認資料仍在；改用 `docker compose down -v` 後資料就會消失
4. **熱更新**：修改 `app/app.py`（因為有 bind mount，不需重新 build），再 `docker compose restart app`

## 常用指令速查

| 指令                            | 用途                                     |
| ------------------------------- | ---------------------------------------- |
| `docker compose up -d`          | 背景啟動所有服務                         |
| `docker compose ps`             | 查看服務狀態                             |
| `docker compose logs -f <服務>` | 持續查看 log                             |
| `docker compose exec <服務> sh` | 進入容器                                 |
| `docker compose restart <服務>` | 重啟單一服務                             |
| `docker compose down`           | 停止並移除容器（保留 volume）            |
| `docker compose down -v`        | 同上，並**刪除 volume（資料會消失）**    |
| `docker compose build`          | 重新 build（compose 有設定 `build:` 時） |

## 常見問題

**Flask 一直顯示「資料庫連線中...」**
MySQL 還在初始化，稍等一下。若超過一分鐘，用 `docker compose logs mysql8` 檢查。

**Flask 回傳 500，log 出現 `Table 'testdb.Product' doesn't exist`**
還沒執行 Step 6 的 SQL 腳本。

**`no matching manifest for linux/arm64/v8`，或 `app` 一直 Restarting 並顯示 `No module named 'pymysql'`**
Docker Hub 上的 `app` image 有問題，請依「關於 image 來源」一節，在本專案目錄重新 build 並推送 multi-arch image。

**`port is already allocated`**
主機的 3306、3307 或 5001 已被占用（例如本機已安裝 MySQL）。修改 `compose.yaml` 中冒號左邊的主機 port 即可。

**啟動時出現 `請在 .env 設定 ...`**
尚未建立 `.env`。執行 `cp .env.example .env`。

**改了 `.env` 的密碼卻沒生效**
MySQL 只在 volume 為空時才會初始化帳密。需要 `docker compose down -v` 清掉 volume 再重新啟動。

## 安全提醒

- 帳號密碼放在 `.env`，已被 `.gitignore` 與 `.dockerignore` 排除，不會被提交或打包進 image。**請勿把 `.env` 推到 Git。**
- `.env.example` 只放佔位值，可安全提交。
- `.env` 內的值預設是學習用的弱密碼，實務上請改成強密碼。
- `compose.yaml` 的 `3306:3306`、`3307:3306` 會對所有網卡開放。在不信任的網路上使用時，建議改成 `"127.0.0.1:3306:3306"`，只允許本機連線。
