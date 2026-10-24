# copy the dependencies to a container
FROM python:3.11-slim
WORKDIR /app
COPY app/requirements.txt .

# setup environment (before image is built)
RUN pip install -r requirements.txt
RUN apt-get update \
    && apt-get install -y nano
EXPOSE 5001

# copy the application code to a container
COPY app/ .

# run the application (image has been built)
CMD ["python", "app.py"]