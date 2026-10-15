INSERT INTO catalog_tracks (id,title,artist,duration,audio_url,artwork_url,status) VALUES
('muwa-01','Muwa Nasheeds','t.me/muwa144',297,'https://muwa-app.floot.app/_cdn/static/0da0908a-391c-4eac-9953-e5ed5c223b67-muwa_track_01.mp3','https://muwa-app.floot.app/_cdn/static/muwa-cover-1.jpg','published'),
('muwa-02','Muwa Nasheed','t.me/muwa144',113,'https://muwa-app.floot.app/_cdn/static/a8fe3a89-66d5-4f3b-8eb6-52e0cce44bc2-muwa_track_02.mp3','https://muwa-app.floot.app/_cdn/static/muwa-cover-2.jpg','published'),
('muwa-03','درب الفداء','t.me/muwa144',153,'https://muwa-app.floot.app/_cdn/static/36e59615-620c-435f-9a2a-e17925f87440-muwa_track_03.mp3','https://muwa-app.floot.app/_cdn/static/muwa-cover-3.jpg','published'),
('muwa-04','Muwa Nasheed · 71s','t.me/muwa144',72,'https://muwa-app.floot.app/_cdn/static/cf558c26-4b41-4125-934f-97b20cb4701f-muwa_track_04.mp3','https://muwa-app.floot.app/_cdn/static/muwa-cover-4.jpg','published'),
('muwa-05','Muwa Nasheeds 2','t.me/muwa144',162,'https://muwa-app.floot.app/_cdn/static/cb3ff162-edc5-4549-b809-06ae6be55159-muwa_track_05.mp3','https://muwa-app.floot.app/_cdn/static/muwa-cover-5.jpg','published'),
('muwa-06','تقدم اخيا لسود الجبال','t.me/muwa144',223,'https://muwa-app.floot.app/_cdn/static/33b5cfd2-c8a5-4dda-8eec-1a9418926655-muwa_track_06.mp3','https://muwa-app.floot.app/_cdn/static/muwa-cover-6.jpg','published'),
('muwa-07','Muwa nasheed','—',314,'https://muwa-app.floot.app/_cdn/static/87fb03cd-8f9d-4767-bb22-db0d3e4e7b80-muwa_track_07.mp3','https://muwa-app.floot.app/_cdn/static/muwa-cover-7.jpg','published')
ON CONFLICT (id) DO NOTHING;
