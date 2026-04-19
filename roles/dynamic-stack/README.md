Media Stack Overview

Self-hosted media ecosystem managed via Docker Compose.
The stack utilizes a collection of specialized applications ("Arr" services) to automate the discovery, downloading, and organization of media, which is then served by a centralized media server.

All services are configured to communicate over a single bridge network ({{ media_stack.network_name }}).
1. Services Description

The configuration includes the following services, which are enabled based on your environment's settings:

Service
	

Image
	

Role & Purpose

Jellyfin
	

jellyfin
	

Media Server (Playback): A way stream your media to any device. It scans the organized media folders (/data/movies, /data/tvshows, etc.) and provides the user interface for playback.

Jellyseerr
	

jellyseerr
	

Request Management: A user-friendly service for managing media requests. Users browse and request movies or shows, which it forwards to the appropriate "Arr" application (Radarr, Sonarr).

qBittorrent
	

qbittorrent
	

Download Client: A lightweight, high-performance torrent client used by the "Arr" services to download requested media files to the shared /downloads volume.

Prowlarr
	

prowlarr
	

Indexer Management: Acts as a centralized proxy for managing and configuring all your torrent trackers and indexers. The "Arr" applications query Prowlarr, which handles searching across multiple indexers.

Sonarr
	

sonarr
	

TV Show Management: Automatically monitors for new TV series and episodes, searches for desired quality, sends the download request, and organizes the final files into the /tv library.

Radarr
	

radarr
	

Movie Management: Automatically monitors for movies, searches for desired quality, sends the download request, and organizes the final files into the /movies library.

Lidarr
	

lidarr
	

Music Management: Automatically monitors for artists and albums, searches for releases, sends the download request, and organizes the final files into the /music library.

Bazarr
	

bazarr
	

Subtitle Management: Integrates with Sonarr and Radarr to automatically search for and download subtitles for your TV shows and movies.

Kavita
	

kavita
	

Reading Server: A media server for reading digital comics, manga, and books.

Suggestarr
	

suggestarr
	

Recommendation System: Automate media content recommendations and download requests based on user activity in media servers like Jellyfin

Releasarr
	

releasarr
	

Release Management: A tool focused on monitoring tool for new music from artists.

Huntarr
	

huntarr
	

Huntarr: Automatic missing content hunter for Sonarr, Radarr, Lidarr, 
2. Service Interaction Diagram (The "Arr" Workflow)

The core functionality of this stack revolves around the automated acquisition pipeline, which connects the user request interface (Jellyseerr) to the download clients (qBittorrent) via the media managers (Radarr/Sonarr/Lidarr) and indexer manager (Prowlarr).

Acuisition Flow:
[will working on this next weekend]
