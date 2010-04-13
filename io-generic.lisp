;;; -*- Mode: Lisp -*-

;;; This software is in the public domain and is
;;; provided with absolutely no warranty.

(in-package #:movies)

(define-compiler-macro read-n-bytes (&whole form bytes stream
                                            &optional (eof-error-p t))
  (if (eql 1 bytes)
      `(read-byte ,stream ,eof-error-p)
      form))

(declaim (inline read-n-bytes))
(defun read-n-bytes (bytes stream &optional (eof-error-p t))
  (declare (type (integer 1 4) bytes)
           (optimize speed))
  (loop with value of-type fixnum = 0
        for low-bit to (* 8 (1- bytes)) by 8
        for byte = (read-byte stream eof-error-p)
        unless byte do (if eof-error-p
                           (error "End of file ~a" stream)
                           (return)) 
        do (setf (ldb (byte 8 low-bit) value) byte)
        finally (return value)))

(defmacro with-io-file ((stream file) &body body)
  `(with-open-file (,stream ,file :element-type '(unsigned-byte 8))
     ,@body))