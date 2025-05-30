(defpackage :sysdef
  (:use :cl)
  (:export
   #:*system-directories*
   #:*cache-directory*
   #:*build-directory*
   #:*registry*
   #:initialize-registry
   #:*component-class-registry*
   #:register-component-class
   #:system
   #:system-directory
   #:system-name
   #:system-description
   #:system-authors
   #:system-homepage
   #:system-licenses
   #:system-version
   #:system-dependencies
   #:system-components
   #:list-system-components
   #:system-file-path
   #:defsystem
   #:unknown-system
   #:unknown-system-name
   #:list-systems
   #:find-system
   #:load-system))

(in-package :sysdef)

(defvar *system-directories* nil
  "The list of directories containing system definition files.")

(defvar *registry* (make-hash-table :test #'equal)
  "The table mapping system names to system instances.")

(defparameter *cache-directory*
  (merge-pathnames
   (make-pathname :directory '(:relative ".cache" "common-lisp" "sysdef"))
   (user-homedir-pathname))
  "The directory used to store data generated by this system.")

(defun build-directory ()
  "Return the path of the directory used to store built components."
  (let ((implementation-type
          (car (list
                #+ccl   "ccl"
                #+clisp "clisp"
                #+sbcl  "sbcl"
                (string-downcase (lisp-implementation-type)))))
        (implementation-version
          (let ((version (lisp-implementation-version)))
            (car
             (list
              #+ccl
              (format nil "~D.~D"
                      ccl::*openmcl-major-version*
                      ccl::*openmcl-minor-version*)
              #+clisp
              ;; E.g. "2.49.93+ (2018-02-18) (built on root2 [65.108.105.205])"
              (subseq version 0 (position #\Space version))
              version))))
        (operating-system
          (car (list
                #+linux "linux"
                #+freebsd "freebsd"
                "unknown")))
        (architecture
          (car (list
                #+(or x86-64                      ; CCL, SBCL
                      x86_64                      ; ECL
                      (and :pc386 :word-size=64)) ; CLISP
                "x64"
                "unknown"))))
    (concatenate 'string
                 implementation-type
                 "-" implementation-version
                 "-" operating-system
                 "-" architecture
                 "/")))

(defvar *build-directory*
  (merge-pathnames (build-directory) *cache-directory*)
  "The directory used to store built components.")

(define-condition unknown-system (error)
  ((name
    :type string
    :initarg :name
    :reader unknown-system-name))
  (:report
   (lambda (condition stream)
     (format stream "unknown system ~S"
             (unknown-system-name condition)))))

(deftype version ()
  "A system version as one of the following forms:

- (<major> <minor> <patch>)
- (<major> <minor> <patch> <pre-release-type> <pre-release-number>)
- (dynamic <shell-command>)
- (custom <version-string>)"
  '(or
    (cons (integer 0)                                             ; major
     (cons (integer 0)                                            ; minor
      (cons (integer 0)                                           ; patch
       (or (cons (member :dev :a :b :rc) (cons (integer 1) null)) ; pre-release
        null))))
    (cons (member dynamic custom) string)))

(defclass system ()
  ((directory
    :type pathname
    :initarg :directory
    :reader system-directory)
   (name
    :type string
    :initarg :name
    :reader system-name)
   (description
    :type (or string null)
    :initarg :description
    :initform nil
    :reader system-description)
   (authors
    :type list
    :initarg :authors
    :initform nil
    :reader system-authors)
   (homepage
    :type (or string null)
    :initarg :homepage
    :initform nil
    :reader system-homepage)
   (licenses
    :type list
    :initarg :licenses
    :initform nil
    :reader system-licenses)
   (version
    :initarg :version
    :initform nil
    :reader system-version)
   (dependencies
    :type list
    :initarg :dependencies
    :initform nil
    :reader system-dependencies)
   (components
    :type list
    :initarg :components
    :initform nil
    :reader system-components)))

(deftype system-designator ()
  '(or system string))

(defmethod print-object ((system system) stream)
  (print-unreadable-object (system stream :type t)
    (prin1 (system-name system) stream)))

(defun normalize-system-name (name)
  "Return the canonical representation of a system name."
  (declare (type string name))
  (string-downcase name))

(defun find-system (name)
  "Return a system indexed in the registry. Signal an UNKNOWN-SYSTEM condition if
there is no system with this name in the registry."
  (declare (type string name))
  (or (gethash (normalize-system-name name) *registry*)
      (error 'unknown-system :name name)))

(defun system (system)
  "Return a system referenced by a system designator."
  (declare (type system-designator system))
  (typecase system
    (system
     system)
    (string
     (find-system system))))

(defvar *component-class-registry* (make-hash-table :test #'equal)
  "The table mapping file types to component classes.")

(defun register-component-class (file-type component-class)
  "Associate a component class to a file type."
  (declare (type string file-type)
           (type (or symbol class) component-class))
  (let ((component-class (if (typep component-class 'class)
                             component-class
                             (find-class component-class))))
    (setf (gethash file-type *component-class-registry*) component-class)))

(defclass component ()
  ((name
    :type string
    :initarg :name
    :reader component-name)
   (path
    :type pathname
    :initarg :path
    :reader component-path)
   (generator
    :type list
    :initarg :generator
    :initform nil
    :reader component-generator)
   (system
    :type system
    :accessor component-system)))

(defmethod print-object ((component component) stream)
  (print-unreadable-object (component stream :type t)
    (prin1 (component-name component) stream)))

(defun component-absolute-path (component)
  (declare (type component component))
  (with-slots (path system) component
    (merge-pathnames path (system-directory system))))

(defun component-build-path (component file-type)
  (declare (type component component)
           (type string file-type))
  (let* ((filename (make-pathname :defaults (component-path component)
                                  :type file-type))
         (system-name (system-name (component-system component)))
         (system-directory
           (merge-pathnames (make-pathname :directory `(:relative ,system-name))
                            *build-directory*)))
    (merge-pathnames filename system-directory)))

(defun component-source-path (component file-type)
  (declare (type component component)
           (type string file-type))
  (if (component-generator component)
      (component-build-path component file-type)
      (component-absolute-path component)))

(defun ensure-component-build-path-exists (component file-type)
  (let ((path (component-build-path component file-type)))
    (ensure-directories-exist path)
    path))

(defun make-component (form)
  "Create a component object from a component definition form."
  (labels ((canonicalize-group-name (name)
             (let ((length (length name)))
               (if (and (> length 0)
                        (char= (char name (1- length)) #\/))
                   (subseq name 0 (1- length))
                   name)))
           (make-component (form directory)
             (cond
               ;; (NAME (FILE1 FILE2 ...))
               ((and (listp form)
                     (= (length form) 2)
                     (stringp (first form))
                     (listp (second form))
                     (not (null (second form))))
                (destructuring-bind (name forms) form
                  (let* ((name (canonicalize-group-name name))
                         (directory-path
                          (make-pathname
                           :directory (reverse (cons name directory))))
                         (children (mapcar
                                    (lambda (form)
                                      (make-component
                                       form (cons name directory)))
                                    forms)))
                    (make-instance 'component-group
                                   :name name
                                   :path directory-path
                                   :children children))))
               ;; NAME
               ((stringp form)
                (make-component (list form) directory))
               ;; (NAME [KEY1 ARG1 KEY2 ARG2 ...])
               ((stringp (car form))
                (let* ((name (car form))
                       (args (cdr form))
                       (path
                        (merge-pathnames (parse-namestring name)
                                         (make-pathname :directory
                                                        (reverse directory))))
                       (type (pathname-type path))
                       (class (or (gethash type *component-class-registry*)
                                  'static-file-component)))
                  (destructuring-bind (&key generator) args
                    (make-instance class :name name :path path
                                         :generator generator))))
               (t
                (error "malformed component ~S" form)))))
    (make-component form (list :relative))))

(defgeneric generate-component (component)
  (:method ((component component))
    (with-slots (generator) component
      (when generator
        (destructuring-bind (package function-symbol &rest args) generator
          (let* ((function
                   (or (find-symbol (string function-symbol) package)
                       (error "generation function ~A not found in package ~A"
                              function-symbol package)))
                 (file-type (pathname-type (component-path component)))
                 (path
                   (ensure-component-build-path-exists component file-type)))
            (with-open-file (stream path :direction :output
                                         :if-exists :supersede
                                         :if-does-not-exist :create)
              (let ((*standard-output* stream))
                (apply function args)))))))))

(defgeneric build-component (component)
  (:method ((component component))
    nil))

(defgeneric load-component (component)
  (:method ((component component))
    nil))

(defgeneric component-children (component)
  (:method ((component component))
    nil))

(defclass static-file-component (component)
  ()
  (:documentation "A file part of the system is not part of any build or load
process."))

(defclass component-group (component)
  ((children
    :type list
    :initarg :children
    :initform nil
    :reader component-group-children))
  (:documentation "A group of components whose source files are stored in a
directory."))

(defmethod component-children ((component component-group))
  (component-group-children component))

(defclass common-lisp-component (component)
  ()
  (:documentation "A Common Lisp source file."))

(register-component-class "lisp" 'common-lisp-component)

(defparameter *common-lisp-fasl-file-type*
  (pathname-type (compile-file-pathname "file.lisp")))

(define-condition common-lisp-file-compilation-failure (error)
  ((source-path
    :type (or pathname string)
    :initarg :source-path
    :reader common-lisp-file-compilation-failure-source-path)
   (error-output
    :type string
    :initarg :error-output
    :reader common-lisp-file-compilation-failure-error-output))
  (:report
   (lambda (condition stream)
     (format stream "cannot compile ~S:~%~@<  ~@;~A~:>~%"
             (common-lisp-file-compilation-failure-source-path condition)
             (common-lisp-file-compilation-failure-error-output condition)))))

(defmethod build-component ((component common-lisp-component))
  (let ((source-path (component-source-path component "lisp"))
        (fasl-path (ensure-component-build-path-exists
                    component *common-lisp-fasl-file-type*))
        (fasl-path-truename nil)
        (warnings nil)
        (failure nil))
    (let ((error-output
            (with-output-to-string (*error-output*)
              (multiple-value-setq (fasl-path-truename warnings failure)
                  (compile-file source-path :output-file fasl-path)))))
      (when failure
        (error 'common-lisp-file-compilation-failure
               :source-path source-path
               :error-output error-output)))))

(defmethod load-component ((component common-lisp-component))
  (load (component-build-path component *common-lisp-fasl-file-type*)))

(defmacro do-system-components ((component system &optional result-form)
                                &body body)
  (let ((system-var (gensym "SYSTEM-")))
    `(let ((,system-var ,system))
       (labels ((iterate (,component)
                  ,@body
                  (mapc #'iterate (component-children ,component))))
         (dolist (,component (system-components ,system-var) ,result-form)
           (iterate ,component))))))

(defun list-system-components (system)
  "Return a list of all the components of SYSTEM. The order of the list corresponds
to a deep-first search of the component tree."
  (let ((components nil))
    (do-system-components (component (system system) (nreverse components))
      (push component components))))

(defun system-file-path (system subpath)
  "Return the absolute pathname of a file in the directory of a system."
  (merge-pathnames subpath (system-directory (system system))))

(defvar *system-directory* nil
  "The current directory while a system manifest is being loaded.")

(defun load-manifest (path)
  "Load a system manifest file at PATH, evaluating the code it contains.
Systems defined in the manifest using DEFSYSTEM are added to the registry."
  (declare (type (or pathname string) path))
  (let* ((package-name (gensym "SYSTEM-TMP-"))
         (package (make-package package-name :use '(:cl :sysdef))))
    (unwind-protect
         (let ((*package* package))
           (load path))
      (delete-package package))))

(defun initialize-registry ()
  "Locate system manifests located in directories listed in *SYSTEM-DIRECTORIES*, load and
validate them and index systems they define in the registry. Systems referenced
in the registry when the function is called are discarded."
  (labels ((pathname-directory-p (path)
             (declare (type pathname path))
             (and (null (pathname-name path))
                  (null (pathname-type path))))
           (load-manifests (paths)
             (declare (type list paths))
             (dolist (path paths)
               (load-manifest path)))
           (find-manifests (path)
             (declare (type pathname path))
             (let ((*system-directory* path))
               (load-manifests
                (directory
                 (make-pathname :defaults path :name :wild :type "cls"))))
             (let ((children
                     (directory (make-pathname :defaults path :name :wild))))
               (dolist (child (delete-if-not #'pathname-directory-p children))
                 (load-manifests (find-manifests child))))))
    (mapc #'find-manifests *system-directories*)
    t))

(defun list-systems ()
  "Return a list of all systems in the registry."
  (let ((systems nil))
    (maphash (lambda (name system)
               (declare (ignore name))
               (push system systems))
             *registry*)
    (sort systems #'string-lessp :key 'system-name)))

(defun load-system (system)
  "Load all the components of a system."
  (declare (type system-designator system))
  (let ((system (system system)))
    (mapc #'load-system (system-dependencies system))
    (do-system-components (component system)
      (generate-component component)
      (build-component component)
      (load-component component))))

(defmacro defsystem (name &key description
                               homepage
                               author authors
                               license licenses
                               version
                               dependencies
                               components)
  "Define and register a system."
  (let ((system (gensym "SYSTEM-"))
        (directory (gensym "DIRECTORY-"))
        (all-licenses (gensym "LICENSES-"))
        (all-authors (gensym "AUTHORS-"))
        (component-objects (gensym "COMPONENT-OBJECTS"))
        (component (gensym "COMPONENT")))
    `(let* ((,directory
              (merge-pathnames *system-directory* *default-pathname-defaults*))
            (,all-authors (append (list ,author) (list ,@authors)))
            (,all-licenses (append (list ,license) (list ,@licenses)))
            (,component-objects (mapcar 'make-component ',components))
            (,system (make-instance 'system :directory ,directory
                                            :name ,name
                                            :description ,description
                                            :homepage ,homepage
                                            :authors ,all-authors
                                            :licenses ,all-licenses
                                            :version ',version
                                            :dependencies ',dependencies
                                            :components ,component-objects)))
       (do-system-components (,component ,system)
         (setf (component-system ,component) ,system))
       (setf (gethash  (system-name ,system) *registry*) ,system)
       ,system)))
