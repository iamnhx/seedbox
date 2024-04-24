import logging
import math
import psutil
import requests
import time
from contextlib import closing
from apscheduler.schedulers.background import BackgroundScheduler

QB_API_URL = "http://localhost:9000"
MAX_SEEDERS = 3
MAX_FILESIZE_BYTES = 50 * 1000 ** 3
DISK_USAGE_THRESHOLD_GB = 5
SKIP_TRACKERS = {"tracker.pterclub.com"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

session = requests.Session()
session.headers.update({'User-Agent': 'qbittorrent-script/1.0'})

start_time = time.time()
total_uploaded_bytes = 0
total_downloaded_bytes = 0
current_hour = time.localtime().tm_hour

def remove_torrent(hash):
    with closing(session.post(QB_API_URL + "/api/v2/torrents/reannounce", data={"hashes": hash})) as response:
        if response.status_code != 200:
            logger.warning(f"Failed to reannounce torrent {hash}")
    with closing(session.post(QB_API_URL + "/api/v2/torrents/delete", data={"hashes": hash, "deleteFiles": "true"})) as response:
        return response.status_code == 200

def set_upload_limit(hash, limit):
    with closing(session.post(QB_API_URL + "/api/v2/torrents/setUploadLimit", data={"hashes": hash, "limit": limit})) as response:
        return response.status_code == 200

def get_torrents():
    with closing(session.get(QB_API_URL + "/api/v2/torrents/info")) as response:
        if response.status_code == 200:
            return response.json()
    return None

def trackers_upload_limit():
    torrents = get_torrents()
    if torrents is not None:
        for torrent in torrents:
            if any(tracker in torrent["magnet_uri"] for tracker in SKIP_TRACKERS):
                continue

            if set_upload_limit(torrent["hash"], "125000000"):
                logger.info(f"Set upload speed limit for torrent {torrent['name']}")
            else:
                logger.warning(f"Failed to set upload speed limit for torrent {torrent['name']}")

def enforce_data_limits():
    global total_uploaded_bytes
    global total_downloaded_bytes
    global start_time
    global current_hour

    # Get the elapsed time since the start of the hour
    elapsed_time = time.time() - start_time

    # If it's the start of a new hour, wait until the next hour to get the new initial number of bytes transmitted
    if current_hour != time.localtime().tm_hour:
        current_hour = time.localtime().tm_hour
        seconds_to_next_hour = (60 - time.localtime().tm_min - 1) * 60 + (60 - time.localtime().tm_sec)
        time.sleep(seconds_to_next_hour)

        # Resume all paused torrents at the start of a new hour
        torrents = get_torrents()
        if torrents is not None:
            for torrent in torrents:
                with closing(session.post(QB_API_URL + "/api/v2/torrents/resume", data={"hashes": torrent["hash"]})) as response:
                    if response.status_code == 200:
                        logger.info(f"Resumed torrent {torrent['name']} at the start of a new hour")
                    else:
                        logger.warning(f"Failed to resume torrent {torrent['name']} at the start of a new hour")

        start_time = time.time()
        total_uploaded_bytes = 0
        total_downloaded_bytes = 0

    # Get the current number of bytes uploaded and downloaded
    try:
        stats = session.get(QB_API_URL + "/api/v2/transfer/info").json()
        total_uploaded_bytes = stats["up_info_data"]  
        total_downloaded_bytes = stats["dl_info_data"] 
    except KeyError:
        logger.warning("Could not retrieve data usage information from the qBittorrent API")
        return

    # If the number of uploaded or downloaded bytes has exceeded the limit, pause all torrents
    if total_uploaded_bytes >= 450 * 1000 ** 3 or total_downloaded_bytes >= 450 * 1000 ** 3:
        torrents = get_torrents()
        if torrents is not None:
            for torrent in torrents:
                with closing(session.post(QB_API_URL + "/api/v2/torrents/pause", data={"hashes": torrent["hash"]})) as response:
                    if response.status_code == 200:
                        logger.info(f"Paused torrent {torrent['name']} to enforce data limits")
                    else:
                        logger.warning(f"Failed to pause torrent {torrent['name']}")

def check_seeders_threshold():
    torrents = get_torrents()
    if torrents is not None:
        for torrent in torrents:
            if torrent["num_complete"] > MAX_SEEDERS:
                if remove_torrent(torrent["hash"]):
                    logger.info(f"""Removed torrent {torrent['name']} Seeders threshold > 3 | {torrent['num_complete']}""")
                else:
                    logger.warning(f"Failed to remove torrent {torrent['name']}")

def remove_torrents_with_filesize_above_threshold():
    torrents = get_torrents()
    if torrents is not None:
        for torrent in torrents:
            if torrent["total_size"] > MAX_FILESIZE_BYTES:
                if remove_torrent(torrent["hash"]):
                    logger.info(f"""Removed torrent {torrent['name']} with filesize = {torrent['total_size'] / (1000 ** 3)} GB""")
                else:
                    logger.warning(f"Failed to remove torrent {torrent['name']}")

def remove_torrents_if_disk_space_below_threshold():
    remaining_space = psutil.disk_usage("/").free / (1000 ** 3)
    if remaining_space < DISK_USAGE_THRESHOLD_GB:
        logger.warning(f"Remaining disk space below {DISK_USAGE_THRESHOLD_GB} GiB. Removing torrents...")
        torrents = get_torrents()
        if torrents is not None:
            for torrent in torrents:
                if remove_torrent(torrent["hash"]):
                    logger.info(f"""Removed torrent {torrent['name']} with filesize = {torrent['total_size'] / (1000 ** 3)} GB""")
                else:
                    logger.warning(f"Failed to remove torrent {torrent['name']}") 

def main():
    scheduler = BackgroundScheduler()
    scheduler.add_job(trackers_upload_limit, 'interval', seconds=5, id='trackers_upload_limit')
    scheduler.add_job(enforce_data_limits, 'interval', seconds=5, id='enforce_data_limits')
    scheduler.add_job(check_seeders_threshold, 'interval', seconds=5, id='check_seeders_threshold')
    scheduler.add_job(remove_torrents_with_filesize_above_threshold, 'interval', seconds=5, id='remove_torrents_with_filesize_above_threshold')
    scheduler.add_job(remove_torrents_if_disk_space_below_threshold, 'interval', minutes=1, id='remove_torrents_if_disk_space_below_threshold')
    scheduler.start()

    try:
        while True:
            time.sleep(1)
    except (KeyboardInterrupt, SystemExit):
        pass
    except Exception as e:
        logger.exception("An error occurred", exc_info=e)
    finally:
        logger.info("Stopping script...")
        if 'scheduler' in locals():
            scheduler.shutdown()
        logger.info("Script stopped.")

if __name__ == '__main__':
    main()