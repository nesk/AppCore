#include "OverlayManager.h"
#include <algorithm>
#include <AppCore/Overlay.h>
#include <Windows.h>

namespace ultralight {

OverlayManager::OverlayManager() {
}

OverlayManager::~OverlayManager() {
}

void OverlayManager::Add(Overlay* overlay) {
  overlays_.push_back(overlay);
}

void OverlayManager::Remove(Overlay* overlay) {
  overlays_.erase(std::remove(overlays_.begin(), overlays_.end(), overlay), overlays_.end());

  if (focused_overlay_ == overlay) {
    focused_overlay_ = nullptr;
    is_dragging_ = false;
  }

  if (hovered_overlay_ == overlay)
    hovered_overlay_ = nullptr;
}

void OverlayManager::Draw() {
  for (auto& i : overlays_)
    i->Draw();
}

void OverlayManager::SetWindowFocused(bool focused) {
  window_focused_ = focused;
  if (focused_overlay_) {
    if (window_focused_)
      focused_overlay_->view()->Focus();
    else
      focused_overlay_->view()->Unfocus();
  }
}

void OverlayManager::FireKeyEvent(const ultralight::KeyEvent& evt) {
  if (focused_overlay_) {
    focused_overlay_->view()->FireKeyEvent(evt);
  }
}

void OverlayManager::FireMouseEvent(const ultralight::MouseEvent& evt) {
  if (is_dragging_) {
    MouseEvent rel_evt = evt;
    rel_evt.x -= hovered_overlay_->x();
    rel_evt.y -= hovered_overlay_->y();

    focused_overlay_->view()->FireMouseEvent(rel_evt);

    if (evt.type == ultralight::MouseEvent::kType_MouseUp && evt.button == MouseEvent::kButton_Left)
      is_dragging_ = false;

    return;
  }

  hovered_overlay_ = HitTest(evt.x, evt.y);

  if (hovered_overlay_ && evt.type == ultralight::MouseEvent::kType_MouseDown 
    && evt.button == MouseEvent::kButton_Left) {
    if (focused_overlay_)
      focused_overlay_->view()->Unfocus();

    focused_overlay_ = hovered_overlay_;

    if (window_focused_)
      focused_overlay_->view()->Focus();
    is_dragging_ = true;
  }

  for (auto& i : overlays_) {
    if (i->is_hidden())
      continue;

    MouseEvent rel_evt = evt;
    rel_evt.x -= i->x();
    rel_evt.y -= i->y();

    i->view()->FireMouseEvent(rel_evt);
  }
}

void OverlayManager::FireScrollEvent(const ultralight::ScrollEvent& evt) {
  if (hovered_overlay_)
    hovered_overlay_->view()->FireScrollEvent(evt);
}

void OverlayManager::FocusOverlay(Overlay* overlay) {
  if (!is_dragging_) {
    if (focused_overlay_)
      focused_overlay_->view()->Unfocus();

    focused_overlay_ = overlay;
    
    if (window_focused_)
      focused_overlay_->view()->Focus();
  }
}

void OverlayManager::UnfocusAll() {
  if (focused_overlay_)
    focused_overlay_->view()->Unfocus();

  focused_overlay_ = nullptr;
}

bool OverlayManager::IsOverlayFocused(Overlay* overlay) const {
  return focused_overlay_ == overlay;
}
    
bool OverlayManager::NeedsRepaint() {
  for (auto& i : overlays_)
    if (i->NeedsRepaint())
      return true;
    
  return false;
}

Overlay* OverlayManager::HitTest(int x, int y) {
  for (auto& i : overlays_) {
    if (!i->is_hidden() && x >= i->x() && y >= i->y() && x < i->x() + (int)i->width() && y < i->y() + (int)i->height())
      return i;
  }

  return nullptr;
}


}  // namespace ultralight
