.PHONY: all app dmg clean

all: app dmg

app:
	./scripts/build.sh

dmg: app
	./scripts/package-dmg.sh

clean:
	rm -rf build dist
