;;; -*- Mode: Lisp -*-

;;; This software is in the public domain and is
;;; provided with absolutely no warranty.

(in-package #:movies)

(defvar *data-file* (merge-pathnames "doc/movies.db" (user-homedir-pathname)))
(defvar *data* (make-hash-table))

(defun objects-of-type (type)
  (gethash type *data*))

(defun (setf objects-of-type) (value type)
  (setf (gethash type *data*) value))

(defun store-object (object)
  (push object (objects-of-type (type-of object))))

(defun clear-data-cache ()
  (clrhash *data*))

(defun delete (object)
  (setf (objects-of-type (type-of object))
        (cl:delete object (objects-of-type (type-of object))))
  (when (typep object 'identifiable)
    (setf (id object) -1))
  t)

(defun map-data (function)
  (maphash function *data*))

(defun map-type (type function)
  (maphash (lambda (key value)
             (when (subtypep key type)
               (map nil function value)))
           *data*))

(defvar *last-id* -1)

;;

(defclass identifiable ()
  ((id :accessor id
       :initarg :id
       :initform nil))
  (:metaclass storable-class))

(defmethod update-instance-for-different-class
    :after ((previous identifiable) (current identifiable) &key)
  (delete previous)
  (store-object current))

(defmethod initialize-instance :after ((object identifiable)
                                       &key id)
  (if (integerp id)
      (setf *last-id* (max *last-id* id))
      (setf (id object) (incf *last-id*))))

;;;

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *codes* #(integer ascii-string
                    identifiable cons
                    string symbol
                    storable-class
                    standard-object)))

(declaim (type simple-vector *codes*))

(defconstant +sequence-length+ 2)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defconstant +integer-length+ 3))
(defconstant +char-length+ 2)

(defconstant +end-of-slots+ 255)

(defconstant +ascii-char-limit+ (code-char 128))

(deftype ascii-string ()
  '(or #+sb-unicode simple-base-string  ; on #-sb-unicode the limit is 255
    (satisfies ascii-string-p)))

(defun ascii-string-p (string)
  (and (stringp string)
       (every (lambda (x)
                (char< x +ascii-char-limit+))
              string)))

;; (defvar *statistics* ())
;; (defun code-type (code)
;;   (let* ((type (aref *codes* code))
;;          (cons (assoc type *statistics*)))
;;     (if cons
;;         (incf (cdr cons))
;;         (push (cons type 1) *statistics*))
;;     type))

(defun code-type (code)
  (aref *codes* code))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (declaim (inline type-code))
  (defun type-code (type)
    (declare (optimize speed (space 0)))
    (position-if (lambda (x) (subtypep type x)) *codes*)))

;;;

(defstruct pointer (id 0 :type fixnum))

(defvar *indexes* (make-hash-table))

(defun index (id)
  (gethash id *indexes*))

(defun (setf index) (object)
  (setf (gethash (id object) *indexes*) object))

(defun slots (class)
  (coerce (remove-if-not #'store-slot-p (class-slots class))
          'simple-vector))

(defun slot-effective-definition (class slot-name)
  (find slot-name (class-slots class) :key #'slot-definition-name))

(defvar *class-cache* (make-array 20 :initial-element nil))
(defvar *class-cache-size* 0)

(defun clear-class-cache ()
  (fill *class-cache* nil)
  (setf *class-cache-size* 0))

(defun class-id (class)
  (position class *class-cache* :end *class-cache-size*))

(defun (setf class-id) (class)
  (setf
   (slots-to-store class) (slots class)
   (aref *class-cache* *class-cache-size*) class)
  (prog1 *class-cache-size*
    (incf *class-cache-size*)))

(defun id-class (id)
  (aref *class-cache* id))

(defun (setf id-class) (class id)
  (setf (aref *class-cache* id) class
        *class-cache-size*
        (max *class-cache-size* (1+ id)))
  class)

;;;

(defgeneric write-object (object stream))
(defgeneric object-size (object))

(defmethod object-size ((object symbol))
  (+ 2 ;; type + length
     (length (symbol-name object))))

(defmethod write-object ((object symbol) stream)
  (write-n-bytes #.(type-code 'symbol) 1 stream)
  (let ((name (symbol-name object)))
    (write-n-bytes (length name) 1 stream)
    (write-ascii-string name stream)))

(defmethod object-size ((object integer))
  (+ 1 +integer-length+))

(defmethod write-object ((object integer) stream)
  (assert (typep object #.`'(unsigned-byte ,(* +integer-length+ 8))))
  (write-n-bytes #.(type-code 'integer) 1 stream)
  (write-n-bytes object +integer-length+ stream))

(defun write-ascii-string (string stream)
  (loop for char across string
        do (write-n-bytes (char-code char) 1 stream)))

(defun write-multibyte-string (string stream)
  (loop for char across string
        do (write-n-bytes (char-code char) +char-length+ stream)))

(defmethod object-size ((string string))
  (+ 1
     +sequence-length+
     (etypecase string
       (ascii-string (length string))
       (string (* (length string)
                  +char-length+)))))

(defmethod write-object ((string string) stream)
  (etypecase string
    #+sb-unicode
    (simple-base-string
     (write-n-bytes #.(type-code 'ascii-string) 1 stream)
     (write-n-bytes (length string) +sequence-length+ stream)
     (write-ascii-string-optimzed (length string) string stream))
    (ascii-string
     (write-n-bytes #.(type-code 'ascii-string) 1 stream)
     (write-n-bytes (length string) +sequence-length+ stream)
     (write-ascii-string string stream))
    (string
     (write-n-bytes #.(type-code 'string) 1 stream)
     (write-n-bytes (length string) +sequence-length+ stream)
     (write-multibyte-string string stream))))

(defmethod object-size ((list cons))
  (let ((count (+ 1 +sequence-length+)))
    (mapc (lambda (x)
            (incf count (object-size x)))
          list)
    count))

(defmethod write-object ((list cons) stream)
  (write-n-bytes #.(type-code 'cons) 1 stream)
  (write-n-bytes (length list) +sequence-length+ stream)
  (dolist (item list)
    (write-object item stream)))

(defmethod object-size ((class storable-class))
  (+ 2
     (object-size (class-name class))
     +sequence-length+ ;; length of list
     (let ((slots (slots class)))
       (setf (slots-to-store class) slots)
       (reduce #'+ slots
               :key (lambda (x)
                      (object-size (slot-definition-name x)))))))

(defmethod write-object ((class storable-class) stream)
  (write-n-bytes #.(type-code 'storable-class) 1 stream)
  (write-object (class-name class) stream)
  (let ((slots (slots-to-store class)))
    (write-n-bytes (length slots) +sequence-length+ stream)
    (loop for slot across slots
          do (write-object (slot-definition-name slot)
                           stream))))

(defmethod object-size ((object identifiable))
  (+ 1 +integer-length+))

(defmethod write-object ((object identifiable) stream)
  (write-n-bytes #.(type-code 'identifiable) 1 stream)
  (write-n-bytes (id object) +integer-length+ stream))

(defun ensure-write-class (class stream)
  (let ((id (class-id class)))
    (cond (id (write-n-bytes id 1 stream))
          (t (setf id (setf (class-id) class))
             (write-n-bytes id 1 stream)
             (write-object class stream)))
    class))

(defvar *counted-classes* nil)
(defun class-size (class)
  (cond ((member class *counted-classes* :test #'eq)
         1) ;; class-id
        (t
         (push class *counted-classes*)
         (object-size class))))

(defun standard-object-size (object)
  (let* ((class (class-of object))
         (slots (slots-to-store class)))
    (declare (type (simple-array t (*)) slots))
    (+ 1 ;; data type
       (class-size class)
       (loop for slot-def across slots
             for i from 0
             for value = (slot-value-using-class class object slot-def)
             unless (eql value (slot-definition-initform slot-def))
             sum (+ 1 ;; slot id
                    (object-size value)))
       1))) ;; end-of-slots

(defun write-standard-object (object stream)
  (write-n-bytes #.(type-code 'standard-object) 1 stream)
  (let ((class (class-of object)))
    (ensure-write-class class stream)
    (loop for slot-def across (slots-to-store class)
          for i from 0
          for value = (slot-value-using-class class object slot-def)
          unless (eql value (slot-definition-initform slot-def))
          do
          (write-n-bytes i 1 stream)
          (write-object value stream))
    (write-n-bytes +end-of-slots+ 1 stream)))

;;;

(defmethod read-object ((type (eql 'storable-class)) stream)
  (let ((class (find-class (read-next-object stream))))
    (unless (class-finalized-p class)
      (finalize-inheritance class))
    (let* ((length (read-n-bytes +sequence-length+ stream))
           (vector (make-array length)))
      (loop for i below length
            do (setf (aref vector i)
                     (slot-effective-definition class
                                                (read-next-object stream))))
      (setf (slots-to-store class)
            vector))
    class))

(defun ensure-read-class (stream)
  (let ((id (read-n-bytes 1 stream)))
    (or (id-class id)
        (setf (id-class id)
              (read-next-object stream)))))

(defmethod read-object ((type (eql 'standard-object)) stream)
  (let* ((class (ensure-read-class stream))
         (instance (make-instance class :id 0))
         (slots (slots-to-store class)))
    (loop for slot-id = (read-n-bytes 1 stream)
          until (= slot-id +end-of-slots+)
          do (setf (slot-value-using-class class instance
                                           (aref slots slot-id))
                   (read-next-object stream)))
    (setf (index) instance)
    (setf *last-id* (max *last-id* (id instance)))
    (store-object instance)
    instance))

(defgeneric read-object (type stream))

(defun read-next-object (stream &optional (eof-error-p t))
  (let ((code (read-n-bytes 1 stream eof-error-p)))
    (when code
      (read-object (code-type code)
                   stream))))

(defun read-symbol (keyword-p stream)
  (intern (read-ascii-string (read-n-bytes 1 stream) stream)
          (if keyword-p
              :keyword
              *package*)))

(defmethod read-object ((type (eql 'keyword)) stream)
  (read-symbol t stream))

(defmethod read-object ((type (eql 'symbol)) stream)
  (read-symbol nil stream))

(defun read-ascii-string (length stream)
  (let ((string (make-string length :element-type 'base-char)))
    #-sbcl
    (loop for i below length
          do (setf (char string i)
                   (code-char (read-n-bytes 1 stream))))
    #+(and sbcl (or x86 x86-64))
    (read-ascii-string-optimized length string stream)
    string))

(defmethod read-object ((type (eql 'ascii-string)) stream)
  (read-ascii-string (read-n-bytes +sequence-length+ stream) stream))

(defmethod read-object ((type (eql 'string)) stream)
  (let* ((length (read-n-bytes +sequence-length+ stream))
         (string (make-string length :element-type 'character)))
    (loop for i below length
          do (setf (char string i)
                   (code-char (read-n-bytes +char-length+ stream))))
    string))

(defmethod read-object ((type (eql 'cons)) stream)
  (loop repeat (read-n-bytes +sequence-length+ stream)
        collect (read-next-object stream)))

(defmethod read-object ((type (eql 'integer)) stream)
  (read-n-bytes +integer-length+ stream))

(defmethod read-object ((type (eql 'identifiable)) stream)
  (make-pointer :id (read-n-bytes  +integer-length+ stream)))

;;;

(defun measure-size ()
  (setf *counted-classes* nil)
  (let ((result 0))
    (map-data (lambda (type objects)
               (declare (ignore type))
               (dolist (object objects)
                 (incf result
                       (standard-object-size object)))))
    result))

(defun dump-data (stream)
  (clear-class-cache)
  (map-data (lambda (type objects)
               (declare (ignore type))
               (dolist (object objects)
                 (write-standard-object object stream)))))

(defun replace-pointers-in-slot (value)
  (typecase value
    (pointer
     (index (pointer-id value)))
    (cons
     (mapl (lambda (x)
             (setf (car x)
                   (replace-pointers-in-slot (car x))))
           value))
    (t value)))

(defun replace-pointers (object)
  (loop with class = (class-of object)
        for slot across (slots-to-store class)
        do (setf (slot-value-using-class class object slot)
                 (replace-pointers-in-slot
                  (slot-value-using-class class object slot)))))

(defgeneric interlink-objects (object))

(defmethod interlink-objects ((object t))
  nil)

;;;

(defun read-file (file)
  (let ((*package* (find-package 'movies)))
    (with-io-file (stream file)
      (loop while (read-next-object stream nil)))))

(defun clear-cashes ()
  (clear-class-cache)
  (clear-data-cache)
  (clrhash *indexes*))

(defun load-data (&optional (file *data-file*))
  (clear-cashes)
  (read-file file)
  (map-data (lambda (type objects)
               (declare (ignore type))
               (dolist (object objects)
                 (replace-pointers object)
                 (interlink-objects object)))))

(defun save-data (&optional (file *data-file*))
  (with-io-file (stream file :direction :output
                        :size (measure-size))
    (dump-data stream)))

;;; Data manipulations

(defgeneric add (type &rest args &key &allow-other-keys))

(defmethod add (type &rest args &key &allow-other-keys)
  (let ((object (apply #'make-instance type args)))
    (store-object object)
    object))

(defun where (&rest clauses)
  (let ((slots (loop for slot in clauses by #'cddr
                     collect (intern (symbol-name slot)
                                     'movies)))
        (values (loop for value in (cdr clauses) by #'cddr collect value)))
    (compile
     nil
     `(lambda (object)
        (with-slots ,slots object
          (and
           ,@(mapcar (lambda (slot value)
                       (typecase value
                         (function
                          `(funcall ,value ,slot))
                         (string
                          `(search ,value ,slot :test #'char-equal))
                         (t
                          `(equalp ,value ,slot))))
                     slots values)))))))

(defun type-and-test (type test)
  (lambda (object) (and (typep object type)
                        (funcall test object))))

(defun lookup (type &optional test)
  (let (results)
    (map-data (lambda (key objects)
                (when (subtypep key type)
                  (setf results
                        (append (if test
                                    (remove-if-not test objects)
                                    objects)
                                results)))))
    (if (= (length results) 1)
        (car results)
        results)))

(defun count (type &optional test)
  (let ((count 0))
    (map-data (lambda (key objects)
                (when (subtypep key type)
                  (incf count
                        (if (null test)
                            (length objects)
                            (count-if test objects))))))
    count))
