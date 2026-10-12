/* Network library setup is outside the first macOS graphics milestone. */
#ifdef __APPLE__
void bbnet_configure(const char *app0, const char *serial, const char *title,
                     const char *version) {
    (void)app0;
    (void)serial;
    (void)title;
    (void)version;
}
#endif
