# DJ9

DJ9 is designed for shared spaces. Each user simply creates an iTunes playlist called "dj9". This needs to be shared on the network.

DJ9 will drive an iTunes instance to rotate through the available "dj9" playlists on the network (it will also run "dj9" on the local instance).

Clone the repository and then run `ruby dj9.rb` after a bundle install. This will kick off the DJ. Hit http://localhost:4567/ to view the upcoming playlist.