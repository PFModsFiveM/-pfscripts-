# Wallpaper Setup Instructions

## Location
Place your wallpaper image at: `pf-tablet/html/wallpaper.jpg`

## Size Recommendations
- Recommended resolution: 1920x1080 or higher
- Aspect ratio: 16:9 (widescreen)
- Format: JPG or PNG
- File size: Keep under 5MB for performance

## Configuration
The wallpaper is already configured in the CSS:
```css
.tablet-screen {
    background: url('wallpaper.jpg') center/cover no-repeat;
}
```

The image will be:
- Centered on the screen
- Scaled to cover the entire tablet display
- Non-repeating

## Apply Changes
After placing wallpaper.jpg:
1. Restart pf-tablet resource
2. Tablet will load the new wallpaper on startup

## Note
Your provided city skyline image should be saved as `wallpaper.jpg` in the pf-tablet/html folder.
