// Tabellone: ciclo giorno/notte condiviso (terreno, oceano, nuvole).
// La carta è letta come un planisfero: x → longitudine, y → latitudine. Il punto subsolare (sun_lon, sun_decl)
// è aggiornato da WorldMap col tempo di gioco. daynight = 0 disattiva tutto (sempre giorno).
uniform float daynight = 0.0;
uniform float sun_lon = 0.0;     // radianti, 0 = meridiano centrale della carta
uniform float sun_decl = 0.17;   // radianti (declinazione)

// coseno dell'angolo zenitale del sole nel punto del mondo (-1..1)
float dn_cos(vec3 wp) {
	vec2 uv = (wp.xz + vec2(80.0, 45.0)) / vec2(160.0, 90.0);
	float lon = (uv.x - 0.5) * 6.2831853;
	float lat = (0.5 - uv.y) * 3.1415927 * 0.92;
	return cos(lat) * cos(sun_decl) * cos(lon - sun_lon) + sin(lat) * sin(sun_decl);
}

// 1 = giorno pieno, 0 = notte; terminatore morbido
float dn_day(vec3 wp) {
	if (daynight < 0.5) return 1.0;
	return smoothstep(-0.13, 0.11, dn_cos(wp));
}

// fascia del crepuscolo (0..1), massima appena dentro il lato illuminato
float dn_twilight(vec3 wp) {
	if (daynight < 0.5) return 0.0;
	float c = dn_cos(wp) - 0.02;
	return exp(-c * c * 160.0);
}
