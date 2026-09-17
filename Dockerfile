FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV STUDY_PLANNER_STATE_DIR=/data
RUN mkdir -p /data
CMD ["python", "-m", "server.start"]
