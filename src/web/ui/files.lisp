;;;; web/ui/files.lisp -- files in pages (spec/files.md 6): FILE-INPUT, a
;;;; form control for one or more files, chosen, dropped or pasted, and
;;;; ATTACHMENTS, a record's files as thumbnails that open the whole image.
;;;;
;;;; Both are HTML first.  The control is an ordinary <input type="file"
;;;; multiple>, laid transparent over a button Tun draws, so the browser's
;;;; own texts, in the browser's language, never show; its script keeps the
;;;; files a person chose, dropped and pasted in that input's own list, so
;;;; the form posts them as it would without a script.  A thumbnail is a
;;;; link to the file itself; its script opens the image in the page's one
;;;; image dialog instead, made when first needed.  What the scripts say is
;;;; in the markup, written in the page's language (spec/i18n.md 3.6).

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +file-accept+ "image/png,image/jpeg,image/webp,image/gif,application/pdf"
  "The types a file control offers: those spec/files.md 2.1 takes.")

(defun octets-text (octets)
  "OCTETS, a file's size, as a person reads it in the current language, in
decimal units: 640 B, 12 kB, 1.4 MB (1,4 MB in Norwegian) (spec/ui.md 6)."
  (cond ((< octets 1000) (tr "~d B" octets))
        ((< octets 1000000) (tr "~d kB" (round octets 1000)))
        (t (tr "~a MB" (number-text (/ (round octets 100000) 10))))))

;;; ------------------------------------------------------------------
;;; The control

(define-component file-input ((&key label name hint error optional label-hidden (max 10)
                                    id attributes))
  (:group "Forms")
  (:doc "A field for one or more files: screenshots, images and PDF. The person chooses
files, drags them into the field or pastes a screenshot, and sees them in a list with
«Remove» before the form is sent. The form must have method=\"post\" and
enctype=\"multipart/form-data\". The browser's file control is the control, laid
transparent over a button in the page's language, so the browser's own texts never show;
without JavaScript it chooses files as ever. MAX is how many files the field takes.")
  (:source "GOV.UK file upload; drag, drop and paste from GOV.UK's multi-file upload pattern")
  (:css (concatenate 'string "
.tun-file-input {
  display: grid;
  /* One column as wide as the field's, never the control's own width: the
     browser's file control is wider than a 320 px phone's column. */
  grid-template-columns: minmax(0, 1fr);
  gap: calc(var(--spacing) * 2);
  padding: calc(var(--spacing) * 3);
  border: 1px dashed " +control-border+ ";
  border-radius: var(--radius-md);
  background-color: var(--input-background);
  transition-property: border-color, background-color;
  transition-duration: var(--duration-fast);
  &[data-dragging] {
    border-color: var(--ring);
    background-color: color-mix(in oklab, var(--accent) 60%, transparent);
  }
  &:has([aria-invalid='true']) { border-color: var(--destructive); }
  /* The browser's control lies transparent over the button and the line
     beside it: a click or a tap there is one on the control, which stays
     the control for the label, the keyboard and a screen reader. */
  & .tun-file-input-picker {
    position: relative;
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 3);
    min-width: 0;
  }
  & .tun-file-input-control {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    margin: 0;
    padding: 0;
    opacity: 0;
    font-size: var(--control-font-size);
    cursor: pointer;
  }
  & .tun-file-input-button {
    display: inline-flex;
    flex: none;
    align-items: center;
    height: var(--control-height);
    padding-inline: calc(var(--spacing) * 3);
    border: 1px solid " +control-border+ ";
    border-radius: var(--radius-md);
    background-color: var(--background);
    color: var(--foreground);
    font-size: var(--control-font-size);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
  }
  & .tun-file-input-picker:has(.tun-file-input-control:focus-visible) .tun-file-input-button {
    box-shadow: var(--focus-ring);
  }
  @media (hover: hover) {
    & .tun-file-input-picker:hover .tun-file-input-button { background-color: var(--accent); }
  }
  & .tun-file-input-status {
    min-width: 0;
    overflow: hidden;
    color: var(--muted-foreground);
    font-size: var(--control-font-size);
    text-overflow: ellipsis;
    white-space: nowrap;
    &[hidden] { display: none; }
  }
  & .tun-file-input-drop, & .tun-file-input-message {
    margin: 0;
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }
  & .tun-file-input-message:empty { display: none; }
  & .tun-file-input-message { color: var(--foreground); }
  & .tun-file-input-list {
    display: grid;
    gap: calc(var(--spacing) * 2);
    margin: 0;
    padding: 0;
    list-style: none;
    &:empty { display: none; }
  }
  & .tun-file-input-item {
    display: grid;
    grid-template-columns: calc(var(--spacing) * 12) minmax(0, 1fr) auto;
    align-items: center;
    gap: calc(var(--spacing) * 3);
  }
  & .tun-file-input-preview {
    width: calc(var(--spacing) * 12);
    height: calc(var(--spacing) * 12);
    border-radius: var(--radius-sm);
    background-color: var(--muted);
    object-fit: cover;
  }
  & span.tun-file-input-preview {
    display: grid;
    place-items: center;
    color: var(--muted-foreground);
  }
  & .tun-file-input-name {
    overflow: hidden;
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  & .tun-file-input-size {
    display: block;
    color: var(--muted-foreground);
    font-size: var(--text-xs);
  }
}"))
  (:script "
// The file control (spec/files.md 6.1): what is chosen, dropped and pasted
// is kept in the input's own list, so the form posts it as without a script.
const fileInputTypes = ['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'application/pdf'];
const fileInputExtensions = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp',
                              'image/gif': 'gif' };
const fileInputMostOctets = 10 * 1024 * 1024;
const fileInputMostTotal = 25 * 1024 * 1024;

// A size as the server writes it (OCTETS-TEXT): SAY holds the zone's texts,
// and the number has the page's language's decimal mark.
const fileInputSize = (octets, say) => {
  if (octets < 1000) return tunText(say.tunFileInputBytes, { size: octets });
  if (octets < 1000000)
    return tunText(say.tunFileInputKilobytes, { size: Math.round(octets / 1000) });
  const megabytes = (Math.round(octets / 100000) / 10)
    .toLocaleString(document.documentElement.lang || undefined, { maximumFractionDigits: 1 });
  return tunText(say.tunFileInputMegabytes, { size: megabytes });
};

// A pasted image a browser named image.png: screenshot-HHMMSS.EXT in the
// page's language, by the device's own clock, with -2, -3 ... when the list
// has that name already.
const fileInputPastedName = (file, taken, say) => {
  const now = new Date();
  const two = (n) => String(n).padStart(2, '0');
  const time = `${two(now.getHours())}${two(now.getMinutes())}${two(now.getSeconds())}`;
  const stem = tunText(say.tunFileInputPastedName, { time });
  const extension = fileInputExtensions[file.type] || 'png';
  let name = `${stem}.${extension}`;
  for (let n = 2; taken.includes(name); n += 1) name = `${stem}-${n}.${extension}`;
  return name;
};

const setUpFileInput = (zone) => {
  const input = zone.querySelector('input[type=file]');
  const list = zone.querySelector('[data-tun-file-input-list]');
  const message = zone.querySelector('[data-tun-file-input-message]');
  const drop = zone.querySelector('[data-tun-file-input-drop]');
  const status = zone.querySelector('[data-tun-file-input-status]');
  const most = Number(zone.dataset.tunFileInputMax || 10);
  const say = zone.dataset;
  const dropText = drop.textContent;
  let chosen = Array.from(input.files);
  let previews = [];

  const show = () => {
    const files = new DataTransfer();
    chosen.forEach((file) => files.items.add(file));
    input.files = files.files;
    previews.forEach((url) => URL.revokeObjectURL(url));
    previews = [];
    // Only a script knows what the control holds: without one the line stays hidden.
    status.textContent = chosen.length === 0 ? say.tunFileInputNone
      : tunText(say.tunFileInputChosenCount, { count: chosen.length });
    status.hidden = false;
    list.replaceChildren(...chosen.map((file, index) => {
      const item = document.createElement('li');
      item.className = 'tun-file-input-item';
      let preview;
      if (file.type.startsWith('image/')) {
        preview = document.createElement('img');
        preview.src = URL.createObjectURL(file);
        preview.alt = '';
        previews.push(preview.src);
      } else {
        preview = document.createElement('span');
        preview.textContent = say.tunFileInputPdf;
      }
      preview.className = 'tun-file-input-preview';
      const text = document.createElement('span');
      text.className = 'tun-file-input-name';
      text.textContent = file.name;
      const size = document.createElement('span');
      size.className = 'tun-file-input-size';
      size.textContent = fileInputSize(file.size, say);
      text.append(size);
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'tun-button';
      remove.dataset.variant = 'ghost';
      remove.dataset.size = 'sm';
      remove.textContent = say.tunFileInputRemove;
      remove.setAttribute('aria-label', tunText(say.tunFileInputRemoveName, { name: file.name }));
      remove.addEventListener('click', () => {
        chosen = chosen.filter((_, i) => i !== index);
        message.textContent = '';
        show();
        input.focus();
      });
      item.append(preview, text, remove);
      return item;
    }));
  };

  const add = (files, pasted) => {
    const notes = [];
    for (let file of files) {
      if (pasted && (file.name === '' || /^image\\.[^.]*$/i.test(file.name))) {
        file = new File([file], fileInputPastedName(file, chosen.map((f) => f.name), say),
                        { type: file.type, lastModified: file.lastModified });
      }
      const total = chosen.reduce((sum, f) => sum + f.size, 0);
      if (!fileInputTypes.includes(file.type)) {
        notes.push(tunText(say.tunFileInputNotAllowed, { name: file.name }));
      } else if (file.size > fileInputMostOctets) {
        notes.push(tunText(say.tunFileInputTooLarge, { name: file.name }));
      } else if (chosen.length >= most) {
        notes.push(tunText(say.tunFileInputTooMany, { most }));
      } else if (total + file.size > fileInputMostTotal) {
        notes.push(say.tunFileInputTooLargeTogether);
      } else {
        chosen.push(file);
      }
    }
    message.textContent = [...new Set(notes)].join(' ');
    show();
  };
  zone.tunAddFiles = add;

  input.addEventListener('change', () => {
    // The browser's own choice replaces the input's list: add it to what
    // was chosen before instead.
    const picked = Array.from(input.files);
    add(picked.filter((file) => !chosen.includes(file)), false);
  });
  let depth = 0;
  zone.addEventListener('dragenter', (event) => {
    if (!event.dataTransfer || !Array.from(event.dataTransfer.types).includes('Files')) return;
    event.preventDefault();
    depth += 1;
    zone.dataset.dragging = '';
    drop.textContent = say.tunFileInputDropHere;
  });
  zone.addEventListener('dragover', (event) => {
    if (!event.dataTransfer || !Array.from(event.dataTransfer.types).includes('Files')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
  });
  const leave = () => {
    depth = 0;
    delete zone.dataset.dragging;
    drop.textContent = dropText;
  };
  zone.addEventListener('dragleave', () => {
    depth -= 1;
    if (depth <= 0) leave();
  });
  zone.addEventListener('drop', (event) => {
    if (!event.dataTransfer || event.dataTransfer.files.length === 0) return;
    event.preventDefault();
    leave();
    add(Array.from(event.dataTransfer.files), false);
  });
  drop.hidden = false;
  show();
};

tunOnContent((root) => {
  const zones = root.querySelectorAll('[data-tun-file-input]:not([data-tun-file-input-ready])');
  for (const zone of zones) {
    zone.dataset.tunFileInputReady = '';
    setUpFileInput(zone);
  }
});

// A paste with files, such as a screenshot, goes to the file control of the
// form it is pasted in, or to the page's only one.  A paste of text alone
// is left to the field it goes into.
document.addEventListener('paste', (event) => {
  const files = Array.from((event.clipboardData && event.clipboardData.files) || []);
  if (files.length === 0) return;
  const form = event.target instanceof Element ? event.target.closest('form') : null;
  const zones = document.querySelectorAll('[data-tun-file-input-ready]');
  const zone = (form && form.querySelector('[data-tun-file-input-ready]'))
    || (zones.length === 1 ? zones[0] : null);
  if (!zone || !zone.tunAddFiles) return;
  event.preventDefault();
  zone.tunAddFiles(files, true);
});")
  (:examples
   (("Screenshots for an item" :layout :stack)
    (file-input (:label "Screenshots" :name "files" :optional t
                        :hint "PNG, JPEG, WebP, GIF or PDF, up to 10 MB each.")))
   (("With an error" :layout :stack)
    (file-input (:label "Receipt" :name "receipt" :max 1
                        :error "“receipt.txt”: this file type is not allowed."))))
  (require-label 'file-input label)
  (let ((id (or id (element-id (or name "file")))))
    (field* (list :label label :for id :hint hint :error error :optional optional
                  :label-hidden label-hidden)
            `(:div ,(attrs (list :class "tun-file-input" :data-tun-file-input t
                                 :data-tun-file-input-max (princ-to-string max))
                           (file-input-texts max))
                   (:div (:@ :class "tun-file-input-picker")
                         (:input ,(attrs (list :class "tun-file-input-control" :type "file" :name name
                                               :multiple (when (> max 1) t) :accept +file-accept+)
                                         (control-attributes id :hint hint :error error)
                                         attributes))
                         ;; Drawn, not a second control: the input is the control.
                         (:span (:@ :class "tun-file-input-button" :aria-hidden "true")
                                ,(if (> max 1) (tr "Choose files") (tr "Choose file")))
                         (:span (:@ :class "tun-file-input-status" :data-tun-file-input-status t
                                    :aria-hidden "true" :hidden t)))
                   (:p (:@ :class "tun-file-input-drop" :data-tun-file-input-drop t :hidden t)
                       ,(tr "Drag files here, or paste a screenshot."))
                   (:p (:@ :class "tun-file-input-message" :data-tun-file-input-message t
                           :role "status"))
                   (:ul (:@ :class "tun-file-input-list" :data-tun-file-input-list t
                            :aria-label ,(tr "Chosen files")))))))

(defun file-input-texts (max)
  "What the file control's script says, as its data-tun-file-input-*
attributes: a plist for ATTRS, in the current language, for a control of
MAX files.  {name}, {most}, {size}, {time} and {count} are the script's to
fill."
  (list :data-tun-file-input-none (if (> max 1) (tr "No files chosen") (tr "No file chosen"))
        :data-tun-file-input-chosen-count (tr "Chosen: {count}")
        :data-tun-file-input-remove (tr "Remove")
        :data-tun-file-input-remove-name (tr "Remove {name}")
        :data-tun-file-input-drop-here (tr "Drop to attach")
        :data-tun-file-input-not-allowed (tr "“{name}”: this file type is not allowed.")
        :data-tun-file-input-too-large (tr "“{name}” is larger than 10 MB.")
        :data-tun-file-input-too-many (tr "You can attach at most {most} files.")
        :data-tun-file-input-too-large-together
        (tr "The files can be at most 25 MB together.")
        :data-tun-file-input-pasted-name (tr "screenshot-{time}")
        :data-tun-file-input-pdf (tr "PDF")
        :data-tun-file-input-bytes (tr "{size} B")
        :data-tun-file-input-kilobytes (tr "{size} kB")
        :data-tun-file-input-megabytes (tr "{size} MB")))

;;; ------------------------------------------------------------------
;;; A record's files

(defun attachment-image-p (item)
  (let ((type (gethash "content_type" item)))
    (and (stringp type) (eql 0 (search "image/" type)))))

(defun attachment-markup (item)
  "One file of ATTACHMENTS: a thumbnail of an image, a tile for a PDF."
  ;; The path, not the tool's URL: the page is on this server, whatever
  ;; host it was reached by.
  (let ((url (format nil "/files/~a" (gethash "id" item)))
        (name (gethash "filename" item))
        (size (octets-text (gethash "size" item 0))))
    (if (attachment-image-p item)
        `(:li (:@ :class "tun-attachments-item")
              (:a (:@ :class "tun-attachments-image" :href ,url :data-tun-attachment-open t
                      :data-tun-attachment-name ,name :aria-label ,(tr "Show ~a" name))
                  (:img (:@ :src ,url :alt ,name :loading "lazy" :decoding "async"
                            :width ,(princ-to-string (gethash "width" item 1))
                            :height ,(princ-to-string (gethash "height" item 1)))))
              (:span (:@ :class "tun-attachments-caption") ,name))
        `(:li (:@ :class "tun-attachments-item")
              (:a (:@ :class "tun-attachments-file" :href ,url :download t)
                  ,(icon (:name :file-text))
                  (:span (:@ :class "tun-attachments-file-type") ,(tr "PDF"))
                  (:span (:@ :class "tun-attachments-size") ,size))
              (:span (:@ :class "tun-attachments-caption") ,name)))))

(define-component attachments ((&key items (label (tr "Attachments"))
                                     (empty (tr "No attachments")) id attributes))
  (:group "Data")
  (:doc "The files attached to a record, from attachments_list: an image as a thumbnail that
opens the whole image, a PDF as a tile that downloads it. The browser scales the image itself
and fetches it only when it is shown. Every attachments on a page opens its images in the
page's one image dialog.")
  (:source "Designsystemet and Aksel file list; the dialog is the HTML <dialog>")
  (:css "
.tun-attachments {
  display: grid;
  gap: calc(var(--spacing) * 2);
  & .tun-attachments-list {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(7rem, 30%), 1fr));
    gap: calc(var(--spacing) * 3);
    margin: 0;
    padding: 0;
    list-style: none;
  }
  & .tun-attachments-item { display: grid; gap: var(--spacing); min-width: 0; }
  & .tun-attachments-image, & .tun-attachments-file {
    display: grid;
    aspect-ratio: 1;
    overflow: hidden;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--muted);
    color: var(--foreground);
    text-decoration: none;
    &:focus-visible { outline: none; box-shadow: var(--focus-ring); }
    @media (hover: hover) {
      &:hover { border-color: var(--border-strong); }
    }
    &:active {
      border-color: var(--border-strong);
      background-image: linear-gradient(var(--pressed), var(--pressed));
    }
  }
  & .tun-attachments-image img { width: 100%; height: 100%; object-fit: cover; }
  & .tun-attachments-file {
    place-content: center;
    justify-items: center;
    gap: var(--spacing);
    font-size: var(--text-xs);
  }
  & .tun-attachments-file-type { font-weight: var(--font-weight-semibold); }
  & .tun-attachments-size { color: var(--muted-foreground); }
  & .tun-attachments-caption {
    overflow: hidden;
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  & .tun-attachments-empty { margin: 0; color: var(--muted-foreground); font-size: var(--text-sm); }
}")
  (:script "
// The page's one image dialog (spec/files.md 6.3): found, or made at the end
// of the body with the texts of the component SAY belongs to.  A file is not
// a page: htmx neither boosts nor preloads its link.
const attachmentsDialog = (say) => {
  const found = document.querySelector('dialog.tun-attachments-dialog');
  if (found) return found;
  const dialog = document.createElement('dialog');
  dialog.className = 'tun-attachments-dialog';
  dialog.setAttribute('aria-label', say.tunAttachmentsImage);
  dialog.setAttribute('hx-boost', 'false');
  dialog.dataset.tunPreload = 'off';
  const full = document.createElement('img');
  full.className = 'tun-attachments-full';
  full.alt = '';
  const bar = document.createElement('div');
  bar.className = 'tun-attachments-bar';
  const name = document.createElement('span');
  name.className = 'tun-attachments-name';
  const actions = document.createElement('span');
  actions.className = 'tun-attachments-actions';
  const original = document.createElement('a');
  original.className = 'tun-button';
  original.dataset.variant = 'outline';
  original.dataset.size = 'sm';
  original.dataset.tunAttachmentOriginal = '';
  original.href = '#';
  original.textContent = say.tunAttachmentsOriginal;
  const form = document.createElement('form');
  form.method = 'dialog';
  const close = document.createElement('button');
  close.className = 'tun-button';
  close.dataset.variant = 'primary';
  close.dataset.size = 'sm';
  close.type = 'submit';
  close.textContent = say.tunAttachmentsClose;
  form.append(close);
  actions.append(original, form);
  bar.append(name, actions);
  dialog.append(full, bar);
  // The focus goes back to the thumbnail that opened it.
  dialog.addEventListener('close', () => {
    if (dialog.tunOpener && dialog.tunOpener.isConnected) dialog.tunOpener.focus();
    dialog.tunOpener = null;
  });
  document.body.append(dialog);
  return dialog;
};

// A thumbnail opens the whole image in the page's dialog.
document.addEventListener('click', (event) => {
  const link = event.target instanceof Element
    && event.target.closest('[data-tun-attachment-open]');
  if (!link || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey) return;
  const component = link.closest('[data-tun-attachments-image]');
  if (!component || typeof HTMLDialogElement !== 'function'
      || typeof HTMLDialogElement.prototype.showModal !== 'function') return;
  event.preventDefault();
  const dialog = attachmentsDialog(component.dataset);
  const full = dialog.querySelector('.tun-attachments-full');
  full.src = link.href;
  full.alt = link.dataset.tunAttachmentName;
  dialog.querySelector('.tun-attachments-name').textContent = link.dataset.tunAttachmentName;
  dialog.querySelector('[data-tun-attachment-original]').href = link.href;
  dialog.tunOpener = link;
  if (!dialog.open) dialog.showModal();
});")
  (:examples
   (("Without files" :layout :stack)
    (attachments (:items '())))
   (("A PDF" :layout :stack)
    (attachments (:items (list (let ((item (make-hash-table :test 'equal)))
                                 (setf (gethash "id" item) "fil_example"
                                       (gethash "filename" item) "receipt.pdf"
                                       (gethash "content_type" item) "application/pdf"
                                       (gethash "size" item) 48211)
                                 item))))))
  (let ((items (coerce items 'list)))
    ;; A file is not a page: htmx neither boosts nor preloads its links.
    ;; The texts of the page's one image dialog, which the script makes
    ;; when an image is first opened.
    `(:div ,(attrs (append (list :class "tun-attachments" :id id :data-tun-preload "off"
                                 :hx-boost\:inherited "false")
                           (when (some #'attachment-image-p items)
                             (list :data-tun-attachments-image (tr "Image")
                                   :data-tun-attachments-original (tr "Open the original")
                                   :data-tun-attachments-close (tr "Close"))))
                   attributes)
           ,(if items
                `(:ul (:@ :class "tun-attachments-list" :aria-label ,label)
                      ,@(mapcar #'attachment-markup items))
                `(:p (:@ :class "tun-attachments-empty") ,empty)))))

;;; The page's one image dialog (spec/files.md 6.3) has its styles here, at
;;; a root of its own, since it sits at the end of the body, in no
;;; attachments.  ATTACHMENTS' script makes its markup, from the texts the
;;; component carries, the first time an image is opened; nothing renders it.
(define-component attachments-dialog ((&key))
  (:internal t)
  (:css "
.tun-attachments-dialog {
  /* The reset takes every margin away; a modal dialog is centred by its
     auto margins. */
  margin: auto;
  max-width: calc(100vw - var(--spacing) * 4);
  max-height: calc(100dvh - var(--spacing) * 4);
  padding: calc(var(--spacing) * 3);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  background-color: var(--popover);
  color: var(--popover-foreground);
  box-shadow: var(--shadow-lg);
  &::backdrop { background-color: color-mix(in oklab, black 60%, transparent); }
  &[open] { display: grid; gap: calc(var(--spacing) * 3); }
  & .tun-attachments-full {
    display: block;
    max-width: 100%;
    max-height: calc(100dvh - var(--spacing) * 24);
    margin-inline: auto;
    object-fit: contain;
  }
  & .tun-attachments-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: calc(var(--spacing) * 2);
    font-size: var(--text-sm);
  }
  & .tun-attachments-name { overflow-wrap: anywhere; }
  & .tun-attachments-actions { display: flex; gap: calc(var(--spacing) * 2); }
}")
  nil)
