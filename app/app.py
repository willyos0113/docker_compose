import os
import time
import pymysql
from flask import Flask, jsonify

app = Flask(__name__)


def get_db_connection():
    while True:
        try:
            return pymysql.connect(
                host=os.environ["DB_HOST"],
                user=os.environ["DB_USER"],
                password=os.environ["DB_PASSWORD"],
                database=os.environ["DB_NAME"],
                cursorclass=pymysql.cursors.DictCursor
            )
        except Exception as e:
            print(f"資料庫連線中...: {e}")
            time.sleep(2)


@app.get("/")
def home():
    connection = get_db_connection()
    try:
        with connection.cursor() as cursor:
            sql = "SELECT Id, Name, Price, Stock, CreatedAt FROM Product"
            cursor.execute(sql)

            rows = cursor.fetchall()

            for row in rows:
                if row['CreatedAt']:
                    row['CreatedAt'] = row['CreatedAt'].strftime(
                        '%Y-%m-%d %H:%M:%S')

            return jsonify(
                status="success",
                product_count=len(rows),
                products=rows
            )
    finally:
        connection.close()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
