(in-package :storage)

(defun build-table (vector)
  (let* ((length (length vector))
         (table (make-array length :element-type 'fixnum)))
    (setf (aref table 0) -1)
    (setf (aref table 1) 0)
    (loop with pos = 2 and candidate = 0
          while (< pos length)
          do (cond ((char-equal (aref vector (1- pos))
                                (aref vector candidate))
                    (setf (aref table pos) (1+ candidate))
                    (incf pos)
                    (incf candidate))
                   ((plusp candidate)
                    (setf candidate (aref table candidate)))
                   (t
                    (setf (aref table pos) 0)
                    (incf pos))))
    table))

(declaim (inline do-kmp))
(defun do-kmp (lower-case upper-case string table)
  (declare (type simple-string lower-case upper-case string)
           (type (simple-array fixnum (*)) table)
           (optimize speed))
  (let ((pattern-length (length lower-case))
        (length (length string)))
   (unless (> pattern-length length)
     (loop with m = 0 and i = 0
           for m+i fixnum = (#+sbcl sb-ext:truly-the #-sbcl the fixnum
                                    (+ m i))
           while (< m+i length)
           for char = (schar string m+i)
           do (cond ((not (or (eql (schar lower-case i) char)
                              (eql (schar upper-case i) char)))
                     (let ((backtrack (aref table i)))
                       (setf m (#+sbcl sb-ext:truly-the #-sbcl the fixnum
                                       (- m+i backtrack))
                             i (max 0 backtrack))))
                    ((= (incf i) pattern-length)
                     (return m)))))))

(defun kmp (sub-sequence sequence &optional table)
  (declare (type vector sequence sub-sequence))
  (let ((sub-length (length sub-sequence))
        (length (length sequence)))
    (cond ((= sub-length 1)
           (position (elt sub-sequence 0) sequence))
          ((= sub-length 0)
           0)
          ((> sub-length length)
           nil)
          (t
           (do-kmp sub-sequence sequence
                   (or table (build-table sub-sequence)))))))